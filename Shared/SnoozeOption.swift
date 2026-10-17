import Foundation

/// Ways to snooze a reminder: from the notification, the in-app alert, or Siri.
enum SnoozeOption: String, CaseIterable, Identifiable, Sendable {
    /// The snooze length chosen in Settings (10 min by default).
    case minutes
    case hour
    case evening
    case tomorrowMorning

    var id: String { rawValue }

    /// Notification action identifier. `.minutes` keeps the original "SNOOZE" id so notifications
    /// scheduled by older versions still work.
    var actionID: String {
        self == .minutes ? "SNOOZE" : "SNOOZE_\(rawValue.uppercased())"
    }

    init?(actionID: String) {
        guard let option = Self.allCases.first(where: { $0.actionID == actionID }) else { return nil }
        self = option
    }

    func title(minutes: Int) -> String {
        switch self {
        case .minutes: return minutes == 60 ? "Snooze 1 hour" : "Snooze \(minutes) min"
        case .hour: return "In 1 Hour"
        case .evening: return "This Evening"
        case .tomorrowMorning: return "Tomorrow Morning"
        }
    }

    var systemImage: String {
        switch self {
        case .minutes: return "clock.arrow.circlepath"
        case .hour: return "hourglass"
        case .evening: return "moon"
        case .tomorrowMorning: return "sunrise"
        }
    }

    static let eveningHour = 18
    static let morningHour = 9

    /// When the reminder should come back.
    /// - This evening: 6 PM, or 3 hours from now once it's already evening.
    /// - Tomorrow morning: 9 AM the next day (or today, if it's still the small hours).
    func date(from now: Date = .now, minutes: Int, calendar: Calendar = .current) -> Date {
        switch self {
        case .minutes:
            return now.addingTimeInterval(TimeInterval(minutes * 60))
        case .hour:
            return now.addingTimeInterval(3600)
        case .evening:
            let evening = calendar.date(bySettingHour: Self.eveningHour, minute: 0, second: 0, of: now) ?? now
            return evening.timeIntervalSince(now) >= 30 * 60 ? evening : now.addingTimeInterval(3 * 3600)
        case .tomorrowMorning:
            let hour = calendar.component(.hour, from: now)
            let day = hour < 4 ? now : (calendar.date(byAdding: .day, value: 1, to: now) ?? now)
            return calendar.date(bySettingHour: Self.morningHour, minute: 0, second: 0, of: day) ?? now
        }
    }
}
