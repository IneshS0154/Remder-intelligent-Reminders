import AppIntents
import CoreLocation
import Foundation
import SwiftData
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

final class NotificationManager {
    static let shared = NotificationManager()

    static let categoryID = "REMINDER"
    static let completeActionID = "COMPLETE"
    static let snoozeActionID = "SNOOZE"
    static var snoozeMinutes: Int { AppSettings.snoozeMinutes }

    /// iOS keeps at most 64 pending local notifications per app; leave headroom for snoozes.
    private static let maxPending = 60
    /// Nag mode: how many follow-ups to send after the due time.
    static let maxNags = 6
    /// Custom repeats can't use one repeating trigger, so the next few occurrences are scheduled
    /// one by one and topped up whenever the app syncs.
    static let customOccurrences = 3
    /// iOS monitors at most 20 regions per app.
    private static let maxLocations = 18

    private let center = UNUserNotificationCenter.current()

    private init() {}

    /// Call again after the snooze length changes so the button title stays accurate.
    func registerCategories() {
        let complete = UNNotificationAction(
            identifier: Self.completeActionID,
            title: "Mark Complete",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "checkmark.circle")
        )
        // Long-press a notification: Complete, then the snooze choices.
        let snoozes = SnoozeOption.allCases.map { option in
            UNNotificationAction(
                identifier: option.actionID,
                title: option.title(minutes: Self.snoozeMinutes),
                options: [],
                icon: UNNotificationActionIcon(systemImageName: option.systemImage)
            )
        }
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [complete] + snoozes,
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorizationIfNeeded() async {
        guard !UITestMode.isActive else { return }  // A permission alert would block UI tests.
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - Scheduling

    func schedule(for reminder: Reminder) {
        guard !reminder.isCompleted else { return }
        if let location = reminder.location {
            // Goes off when you arrive at or leave the place; iOS watches the area.
            guard reminder.notificationEnabled else { return }
            let trigger = UNLocationNotificationTrigger(region: location.region, repeats: location.repeats)
            center.add(UNNotificationRequest(identifier: reminder.id.uuidString, content: content(for: reminder), trigger: trigger))
            return
        }
        scheduleNags(for: reminder)
        guard reminder.notificationEnabled else { return }
        // A one-off reminder in the past would never fire; the list shows it as overdue instead.
        guard reminder.repeatFrequency != .none || reminder.dueDate > .now else { return }

        let calendar = Calendar.current
        let comps: DateComponents
        let repeats: Bool

        switch reminder.repeatFrequency {
        case .custom:
            scheduleCustomOccurrences(for: reminder)
            return
        case .none:
            comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.dueDate)
            repeats = false
        case .daily:
            comps = calendar.dateComponents([.hour, .minute], from: reminder.dueDate)
            repeats = true
        case .weekly:
            comps = calendar.dateComponents([.weekday, .hour, .minute], from: reminder.dueDate)
            repeats = true
        case .monthly:
            // Note: reminders scheduled for days 29-31 will be skipped in shorter months.
            comps = calendar.dateComponents([.day, .hour, .minute], from: reminder.dueDate)
            repeats = true
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
        let request = UNNotificationRequest(identifier: reminder.id.uuidString, content: content(for: reminder), trigger: trigger)
        center.add(request)
    }

    /// The next few occurrences of a custom repeat, each as a one-off notification.
    private func scheduleCustomOccurrences(for reminder: Reminder) {
        let calendar = Calendar.current
        var date: Date? = reminder.dueDate > .now ? reminder.dueDate : reminder.nextOccurrence(after: .now)
        for index in 0..<Self.customOccurrences {
            guard let fireDate = date else { break }
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: occurrenceID(for: reminder, index), content: content(for: reminder), trigger: trigger))
            date = reminder.nextOccurrence(after: fireDate)
        }
    }

    /// The first occurrence uses the reminder's own ID, so it's replaced like any other.
    private func occurrenceID(for reminder: Reminder, _ index: Int) -> String {
        index == 0 ? reminder.id.uuidString : "\(reminder.id.uuidString)-occ-\(index)"
    }

    /// Removes the reminder's notifications, alarm and Live Activity.
    func cancel(for reminder: Reminder) {
        cancelNotifications(for: reminder)
        AlarmScheduler.shared.cancel(reminderID: reminder.id)
        LiveActivityManager.shared.end(reminderID: reminder.id)
        reloadWidgets()
    }

    /// Re-registers notifications, the alarm and the Live Activity after the reminder changed.
    func reschedule(for reminder: Reminder) {
        cancelNotifications(for: reminder)
        schedule(for: reminder)
        AlarmScheduler.shared.sync(reminder)
        LiveActivityManager.shared.sync(reminder, restart: true)
        reloadWidgets()
    }

    private func cancelNotifications(for reminder: Reminder) {
        let ids = [snoozeID(for: reminder)] + nagIDs(for: reminder)
            + (0..<Self.customOccurrences).map { occurrenceID(for: reminder, $0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: - Nag mode

    /// Follow-up notifications every `nagIntervalMinutes` after the due time, until the reminder
    /// is completed (completing cancels them). For repeating reminders they follow the current
    /// occurrence while it's still being nagged about, otherwise the next one.
    private func scheduleNags(for reminder: Reminder) {
        let interval = TimeInterval(reminder.nagIntervalMinutes * 60)
        guard interval > 0, !reminder.isLocationBased, reminder.notificationEnabled || reminder.alarmEnabled,
              let base = nagBase(for: reminder, interval: interval) else { return }

        let calendar = Calendar.current
        for k in 1...Self.maxNags {
            let fireDate = base.addingTimeInterval(interval * Double(k))
            guard fireDate > .now else { continue }
            let content = content(for: reminder)
            content.title = "Still not done: \(reminder.title)"
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: nagID(for: reminder, k), content: content, trigger: trigger))
        }
    }

    private func nagBase(for reminder: Reminder, interval: TimeInterval) -> Date? {
        let window = interval * Double(Self.maxNags)
        if let latest = reminder.latestOccurrence(onOrBefore: .now), Date.now.timeIntervalSince(latest) < window {
            return latest
        }
        let upcoming = reminder.upcomingDueDate
        return upcoming > .now ? upcoming : nil
    }

    private func nagIDs(for reminder: Reminder) -> [String] {
        (1...Self.maxNags).map { nagID(for: reminder, $0) }
    }

    private func nagID(for reminder: Reminder, _ k: Int) -> String {
        "\(reminder.id.uuidString)-nag-\(k)"
    }

    /// Rebuilds all pending notifications from stored reminders, soonest first.
    func resync(reminders: [Reminder]) async {
        // Keep snoozes; they aren't derivable from stored data.
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { !$0.hasSuffix("-snooze") }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        // The daily brief goes first; it's a handful of notifications at most.
        var budget = Self.maxPending - BriefScheduler.shared.schedule(reminders: reminders)

        // Location reminders have their own limit (iOS watches at most 20 places).
        let places = reminders.filter { !$0.isCompleted && $0.isLocationBased && $0.notificationEnabled }
        for reminder in places.prefix(Self.maxLocations) where budget > 0 {
            budget -= 1
            schedule(for: reminder)
        }

        // Then the rest, soonest first; nag follow-ups and custom repeats cost more than one.
        let candidates = reminders
            .filter { !$0.isCompleted && !$0.isLocationBased && ($0.repeats || $0.dueDate > .now || $0.nagIntervalMinutes > 0) }
            .sorted { $0.upcomingDueDate < $1.upcomingDueDate }
        for reminder in candidates {
            let alerts = reminder.repeatFrequency == .custom ? Self.customOccurrences : 1
            let cost = (reminder.notificationEnabled ? alerts : 0) + (reminder.nagIntervalMinutes > 0 ? Self.maxNags : 0)
            guard cost <= budget else { break }
            budget -= cost
            schedule(for: reminder)
        }
        AlarmScheduler.shared.resync(reminders: reminders)
        LiveActivityManager.shared.resync(reminders: reminders)
        reloadWidgets()
        #if DEBUG
        logPending()
        #endif
    }

    #if DEBUG
    /// Lists what's scheduled, for checking in the Xcode console.
    func logPending() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            for category in await center.notificationCategories() {
                print("Remder: actions for \(category.identifier): \(category.actions.map(\.title).joined(separator: " | "))")
            }
            let requests = await center.pendingNotificationRequests()
            print("Remder: \(requests.count) pending notifications")
            for request in requests {
                let when: String
                switch request.trigger {
                case let trigger as UNCalendarNotificationTrigger:
                    when = trigger.nextTriggerDate()?.formatted(date: .abbreviated, time: .shortened) ?? "?"
                case let trigger as UNLocationNotificationTrigger:
                    let region = trigger.region as? CLCircularRegion
                    when = "place \(region?.center.latitude ?? 0),\(region?.center.longitude ?? 0) r=\(Int(region?.radius ?? 0)) entry=\(trigger.region.notifyOnEntry)"
                case let trigger as UNTimeIntervalNotificationTrigger:
                    when = "in \(Int(trigger.timeInterval))s"
                default:
                    when = "-"
                }
                print("  \(request.identifier) | \(request.content.title) | \(when)")
            }
        }
    }
    #endif

    // MARK: - Actions

    /// Completes a one-off reminder, or advances a repeating one to its next occurrence.
    /// The caller is responsible for saving the model context.
    func complete(_ reminder: Reminder) {
        // Record which occurrence was done, for streaks: the latest one that's come due, or the
        // upcoming one when completing early.
        let occurrence = reminder.isLocationBased ? Date.now : (reminder.latestOccurrence(onOrBefore: .now) ?? reminder.dueDate)
        reminder.completions.append(Completion(occurrenceDate: occurrence))

        // "Every time I get home" stays active; its notification repeats on its own.
        if reminder.location?.repeats == true {
            reloadWidgets()
            return
        }

        // Completing early skips the upcoming occurrence rather than leaving it in place.
        if let next = reminder.nextOccurrence(after: max(.now, reminder.dueDate)) {
            reminder.dueDate = next
            reschedule(for: reminder)
        } else {
            reminder.isCompleted = true
            reminder.completedDate = .now
            cancel(for: reminder)
        }
    }

    /// Un-ticks a completed one-off reminder and drops its completion record.
    func uncomplete(_ reminder: Reminder) {
        reminder.isCompleted = false
        reminder.completedDate = nil
        if let last = reminder.completions.max(by: { $0.completedAt < $1.completedAt }) {
            last.modelContext?.delete(last)
        }
        reschedule(for: reminder)
    }

    func snooze(_ reminder: Reminder, minutes: Int = snoozeMinutes) {
        snooze(reminder, until: .now.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    func snooze(_ reminder: Reminder, option: SnoozeOption) {
        snooze(reminder, until: option.date(minutes: Self.snoozeMinutes))
    }

    /// Brings the reminder back at `date` (one snooze per reminder; a new one replaces it).
    func snooze(_ reminder: Reminder, until date: Date) {
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let content = content(for: reminder)
        center.add(UNNotificationRequest(identifier: snoozeID(for: reminder), content: content, trigger: trigger))
        LiveActivityManager.shared.snooze(reminder, until: date)
    }

    // MARK: - Helpers

    private func notificationSound() -> UNNotificationSound? {
        let sound = AppSettings.sound
        switch sound {
        case .standard: return .default
        case .silent: return nil
        default: return sound.fileName.map { UNNotificationSound(named: UNNotificationSoundName($0)) } ?? .default
        }
    }

    /// Called after any reminder change: widgets, Siri phrases and today's brief follow along.
    func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        // Keeps Siri's "Mark <reminder> as done" phrases in step with the reminder list.
        RemderShortcuts.updateAppShortcutParameters()
        BriefScheduler.shared.refreshSoon()
    }

    private func snoozeID(for reminder: Reminder) -> String {
        reminder.id.uuidString + "-snooze"
    }

    private func content(for reminder: Reminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        if let notes = reminder.notes, !notes.isEmpty {
            content.body = notes
        } else if let note = reminder.note, !note.isEmpty {
            // Show the attached note so the alert carries the detail.
            let preview = note.preview
            content.body = preview.isEmpty ? note.displayTitle : "\(note.displayTitle): \(preview)"
        } else {
            content.body = reminder.location?.summary ?? "Reminder due"
        }
        content.sound = notificationSound()
        content.categoryIdentifier = Self.categoryID
        content.interruptionLevel = reminder.priority == .high ? .timeSensitive : .active
        content.userInfo = ["reminderID": reminder.id.uuidString]
        return content
    }
}
