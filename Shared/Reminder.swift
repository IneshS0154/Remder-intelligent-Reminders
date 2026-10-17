import Foundation
import SwiftData

enum Priority: Int, Codable, CaseIterable, Identifiable {
    case low = 0
    case medium = 1
    case high = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

enum RepeatFrequency: Int, Codable, CaseIterable, Identifiable {
    case none = 0
    case daily = 1
    case weekly = 2
    case monthly = 3
    /// Anything else: the rule is stored in `Reminder.repeatRuleData`.
    case custom = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return "Never"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .custom: return "Custom"
        }
    }

    /// The equivalent recurrence rule (nil for `.none` and `.custom`).
    var presetRule: RepeatRule? {
        switch self {
        case .none, .custom: return nil
        case .daily: return .daily(calendar: .current)
        case .weekly: return .weekly(calendar: .current)
        case .monthly: return .monthly(calendar: .current)
        }
    }
}

@Model
final class Reminder {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String?
    var dueDate: Date
    var priority: Priority
    var category: String
    var isCompleted: Bool
    var completedDate: Date?
    var repeatFrequency: RepeatFrequency
    var createdDate: Date
    /// Minutes before `dueDate` to start the Dynamic Island countdown; 0 turns it off.
    var liveActivityLeadMinutes: Int = 0
    /// Optional detailed note (managed in the Notes section).
    var note: Note?
    /// How to be reminded: a notification, a full-screen alarm, and/or the Live Activity (lead > 0).
    var notificationEnabled: Bool = true
    var alarmEnabled: Bool = false
    /// Nag mode: minutes between follow-up notifications after the due time until it's done; 0 = off.
    var nagIntervalMinutes: Int = 0
    /// History of completed occurrences, used for streaks and stats.
    @Relationship(deleteRule: .cascade, inverse: \Completion.reminder)
    var completions: [Completion] = []
    /// A custom repeat (`Calendar.RecurrenceRule` as JSON) when `repeatFrequency` is `.custom`.
    var repeatRuleData: Data? = nil
    /// For location reminders: where it goes off (`ReminderLocation` as JSON). Nil = at a time.
    var locationData: Data? = nil

    init(
        title: String,
        notes: String? = nil,
        dueDate: Date,
        priority: Priority = .medium,
        category: String = "",
        repeatFrequency: RepeatFrequency = .none,
        liveActivityLeadMinutes: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
        self.category = category
        self.isCompleted = false
        self.completedDate = nil
        self.repeatFrequency = repeatFrequency
        self.createdDate = .now
        self.liveActivityLeadMinutes = liveActivityLeadMinutes
    }
}

extension Reminder {
    /// The repeat, as a recurrence rule: a preset's rule, the stored custom rule, or nil.
    /// Setting a rule that matches a preset stores it as that preset.
    var repeatRule: RepeatRule? {
        get {
            if repeatFrequency == .custom {
                return repeatRuleData.flatMap { try? JSONDecoder().decode(RepeatRule.self, from: $0) }
            }
            return repeatFrequency.presetRule
        }
        set {
            if let newValue, let preset = newValue.preset {
                repeatFrequency = preset
                repeatRuleData = nil
            } else if let newValue {
                repeatFrequency = .custom
                repeatRuleData = try? JSONEncoder().encode(newValue)
            } else {
                repeatFrequency = .none
                repeatRuleData = nil
            }
        }
    }

    var repeats: Bool { repeatFrequency != .none }

    /// "Daily", "Every 2 weeks on Mon, Wed", "Never".
    var repeatSummary: String {
        repeatFrequency == .custom ? (repeatRule?.summary ?? "Custom") : repeatFrequency.label
    }

    /// Where a location reminder goes off; nil for reminders at a time.
    var location: ReminderLocation? {
        get { locationData.flatMap { try? JSONDecoder().decode(ReminderLocation.self, from: $0) } }
        set { locationData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var isLocationBased: Bool { locationData != nil }

    /// A custom repeat starts on its first matching day: set on a Thursday to repeat on Mondays
    /// and Wednesdays, it's first due the next Monday or Wednesday at the same time.
    func snapToRepeatRule() {
        guard repeatFrequency == .custom, let rule = repeatRule,
              let first = rule.firstOccurrence(onOrAfter: dueDate) else { return }
        dueDate = first
    }

    /// The next time this reminder will fire: its due date, or for a repeating reminder whose
    /// due date has passed, the next occurrence.
    var upcomingDueDate: Date {
        dueDate > .now ? dueDate : (nextOccurrence() ?? dueDate)
    }

    var isOverdue: Bool {
        !isCompleted && !isLocationBased && dueDate < .now
    }

    /// The most recent occurrence at or before `date`, or nil if none has happened yet.
    func latestOccurrence(onOrBefore date: Date = .now) -> Date? {
        guard dueDate <= date else { return nil }
        guard repeatFrequency != .none else { return dueDate }
        var latest = dueDate
        while let next = nextOccurrence(after: latest), next <= date {
            latest = next
        }
        return latest
    }

    /// Calendar unit between occurrences of a repeating reminder.
    var repeatComponent: Calendar.Component? {
        switch repeatFrequency {
        case .none: return nil
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .custom: return repeatRule?.unit
        }
    }

    /// The first occurrence of this repeating reminder strictly after `date`, or nil if it doesn't
    /// repeat (or a custom repeat has ended).
    func nextOccurrence(after date: Date = .now) -> Date? {
        let component: Calendar.Component
        switch repeatFrequency {
        case .none: return nil
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        case .custom:
            // Anchored at the due date, so "every 2 weeks" keeps its rhythm as the due date moves on.
            guard let rule = repeatRule else { return nil }
            return rule.recurrences(of: dueDate, in: date..<Date.distantFuture).first { $0 > date }
        }

        let calendar = Calendar.current
        var step = 1
        var next = dueDate
        while next <= date {
            // Add from the original date each time so monthly reminders on the 31st don't drift to the 28th.
            guard let candidate = calendar.date(byAdding: component, value: step, to: dueDate) else { return nil }
            next = candidate
            step += 1
        }
        return next
    }
}
