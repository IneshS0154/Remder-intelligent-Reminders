import Foundation
import SwiftData
import UserNotifications

/// The daily brief: a morning summary ("5 reminders today: …") and an evening check-in
/// ("2 still to do today: …").
///
/// Local notifications can't change after they're scheduled, so the next week's briefs are
/// rebuilt whenever reminders change. If nothing changes, the reminders are still open, so the
/// text scheduled ahead of time stays right.
final class BriefScheduler {
    static let shared = BriefScheduler()
    static let daysAhead = 7

    private let center = UNUserNotificationCenter.current()
    private var pending: Task<Void, Never>?

    private init() {}

    enum Kind: String {
        case morning, evening
    }

    /// Replaces all brief notifications. Returns how many were scheduled.
    @discardableResult
    func schedule(reminders: [Reminder], now: Date = .now) -> Int {
        center.removePendingNotificationRequests(withIdentifiers: Self.allIDs(from: now))
        let requests = Self.requests(for: reminders, now: now)
        requests.forEach { center.add($0) }
        return requests.count
    }

    /// Rebuilds shortly after a change, batching several quick changes into one.
    func refreshSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let reminders = (try? RemderApp.sharedContainer.mainContext.fetch(FetchDescriptor<Reminder>())) ?? []
            schedule(reminders: reminders)
        }
    }

    // MARK: - Building the notifications

    static func requests(for reminders: [Reminder], now: Date) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        var requests: [UNNotificationRequest] = []
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            for kind in enabledKinds {
                guard let fireDate = fireDate(kind, on: day), fireDate > now,
                      let text = summary(kind, reminders: reminders, day: day, at: fireDate) else { continue }
                let content = UNMutableNotificationContent()
                content.title = text.title
                content.body = text.body
                content.sound = .default
                content.threadIdentifier = "brief"
                content.interruptionLevel = .active
                let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                requests.append(UNNotificationRequest(identifier: id(kind, day: day), content: content, trigger: trigger))
            }
        }
        return requests
    }

    private static var enabledKinds: [Kind] {
        (AppSettings.morningBriefEnabled ? [.morning] : []) + (AppSettings.eveningCheckInEnabled ? [.evening] : [])
    }

    private static func fireDate(_ kind: Kind, on day: Date) -> Date? {
        let minutes = kind == .morning ? AppSettings.morningBriefMinutes : AppSettings.eveningCheckInMinutes
        return Calendar.current.date(byAdding: .minute, value: minutes, to: day)
    }

    /// The brief's text, or nil when there's nothing worth sending.
    static func summary(_ kind: Kind, reminders: [Reminder], day: Date, at time: Date) -> (title: String, body: String)? {
        let calendar = Calendar.current
        guard let dayInterval = calendar.dateInterval(of: .day, for: day) else { return nil }
        let items = reminders
            .flatMap { reminder in occurrences(of: reminder, in: dayInterval).map { (reminder.title, $0) } }
            .sorted { $0.1 < $1.1 }

        switch kind {
        case .morning:
            // One-off reminders already past due by the time the brief arrives.
            let overdue = reminders.filter { !$0.isCompleted && !$0.isLocationBased && !$0.repeats && $0.dueDate < dayInterval.start }.count
            guard !items.isEmpty || overdue > 0 else { return nil }
            var body: String
            if items.isEmpty {
                body = "Nothing new today."
            } else {
                let listed = items.prefix(3).map { "\($0.0) \($0.1.formatted(date: .omitted, time: .shortened))" }
                body = "\(items.count) reminder\(items.count == 1 ? "" : "s") today: " + list(listed, total: items.count)
            }
            if overdue > 0 { body += " \(overdue) overdue." }
            return ("Good morning", body)

        case .evening:
            guard !items.isEmpty else { return nil }
            let names = items.map(\.0)
            let body = "\(items.count) still to do today: " + list(Array(names.prefix(3)), total: names.count)
            return ("Evening check-in", body)
        }
    }

    /// Times this reminder is due within `interval` (repeats included).
    static func occurrences(of reminder: Reminder, in interval: DateInterval) -> [Date] {
        guard !reminder.isCompleted, !reminder.isLocationBased else { return [] }
        var dates: [Date] = []
        var next: Date? = reminder.dueDate >= interval.start
            ? reminder.dueDate
            : reminder.nextOccurrence(after: interval.start.addingTimeInterval(-1))
        while let date = next, date < interval.end, dates.count < 48 {
            if date >= interval.start { dates.append(date) }
            next = reminder.nextOccurrence(after: date)
        }
        return dates
    }

    /// "A, B and C." / "A, B, C and 2 more."
    private static func list(_ items: [String], total: Int) -> String {
        let extra = total - items.count
        if extra > 0 { return items.joined(separator: ", ") + " and \(extra) more." }
        guard items.count > 1 else { return (items.first ?? "") + "." }
        return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "") + "."
    }

    /// "brief-morning-2026-09-27", using the local date (ISO formatting would use UTC).
    private static func id(_ kind: Kind, day: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "brief-%@-%04d-%02d-%02d", kind.rawValue, parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// IDs for yesterday through the week ahead, so a changed schedule leaves nothing behind.
    private static func allIDs(from now: Date) -> [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (-1...daysAhead).flatMap { offset -> [String] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
            return [id(.morning, day: day), id(.evening, day: day)]
        }
    }
}
