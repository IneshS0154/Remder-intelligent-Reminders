import Foundation

/// Repeats beyond the simple presets use Foundation's `Calendar.RecurrenceRule`: every N days,
/// weeks, months or years, specific weekdays, "last Friday of the month" and an end date.
/// Daily, weekly and monthly stay as `RepeatFrequency` presets (see `Reminder.repeatRule`).
typealias RepeatRule = Calendar.RecurrenceRule

nonisolated extension Calendar.RecurrenceRule {
    /// Monday to Friday.
    static func weekdays(calendar: Calendar = .current) -> Self {
        Self(calendar: calendar, frequency: .weekly, weekdays: Locale.Weekday.workdays.map { .every($0) })
    }

    static func everyTwoWeeks(calendar: Calendar = .current) -> Self {
        Self(calendar: calendar, frequency: .weekly, interval: 2)
    }

    /// The preset this rule is equivalent to, if any (plain daily, weekly or monthly).
    var preset: RepeatFrequency? {
        guard interval == 1, weekdays.isEmpty, daysOfTheMonth.isEmpty, months.isEmpty,
              daysOfTheYear.isEmpty, weeks.isEmpty, setPositions.isEmpty, end == .never else { return nil }
        switch frequency {
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        default: return nil
        }
    }

    /// Calendar unit between repeats.
    var unit: Calendar.Component {
        switch frequency {
        case .minutely: return .minute
        case .hourly: return .hour
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .yearly: return .year
        @unknown default: return .day
        }
    }

    var endDate: Date? {
        end.date
    }

    /// Weekdays in the order the week starts, for "every" (not nth) weekday rules.
    var everyWeekdays: [Locale.Weekday] {
        weekdays.compactMap { weekday -> Locale.Weekday? in
            guard case .every(let day) = weekday else { return nil }
            return day
        }
    }

    /// "Every 2 weeks on Mon, Wed", "Weekdays", "Last Friday of every month", "Every 3 days until 30 Oct".
    var summary: String {
        var text: String
        switch frequency {
        case .daily:
            text = interval == 1 ? "Daily" : "Every \(interval) days"
        case .weekly:
            let days = Set(everyWeekdays)
            if interval == 1, days == Set(Locale.Weekday.workdays) {
                text = "Weekdays"
            } else if interval == 1, days == [.saturday, .sunday] {
                text = "Weekends"
            } else {
                text = interval == 1 ? "Weekly" : "Every \(interval) weeks"
                if !days.isEmpty {
                    text += " on " + Locale.Weekday.ordered.filter(days.contains).map(\.shortName).joined(separator: ", ")
                }
            }
        case .monthly:
            let every = interval == 1 ? "every month" : "every \(interval) months"
            if case .nth(let n, let day)? = weekdays.first {
                text = "\(Self.ordinalWord(n)) \(day.fullName) of \(every)"
            } else if let day = daysOfTheMonth.first {
                text = (interval == 1 ? "Monthly" : "Every \(interval) months") + " on the \(day == -1 ? "last day" : Self.ordinal(day))"
            } else {
                text = interval == 1 ? "Monthly" : "Every \(interval) months"
            }
        case .yearly:
            text = interval == 1 ? "Yearly" : "Every \(interval) years"
        default:
            text = "Custom"
        }
        if let endDate {
            text += " until \(endDate.formatted(.dateTime.day().month(.abbreviated)))"
        }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    /// 1 → "First", -1 → "Last".
    static func ordinalWord(_ n: Int) -> String {
        switch n {
        case 1: return "First"
        case 2: return "Second"
        case 3: return "Third"
        case 4: return "Fourth"
        case -1: return "Last"
        default: return ordinal(n)
        }
    }

    /// The first time at or after `date` that matches the rule (a reminder set for a Thursday with
    /// a Mon/Wed rule starts on the next Monday or Wednesday).
    func firstOccurrence(onOrAfter date: Date) -> Date? {
        recurrences(of: date).first { _ in true }
    }
}

nonisolated extension Locale.Weekday {
    /// Sunday first, matching `Calendar.component(.weekday:)` (1 = Sunday).
    static let ordered: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
    static let workdays: [Locale.Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]

    init(date: Date, calendar: Calendar = .current) {
        self = Self.ordered[calendar.component(.weekday, from: date) - 1]
    }

    /// "Mon".
    var shortName: String {
        Calendar.current.shortWeekdaySymbols[Self.ordered.firstIndex(of: self) ?? 0]
    }

    /// "Monday".
    var fullName: String {
        Calendar.current.weekdaySymbols[Self.ordered.firstIndex(of: self) ?? 0]
    }

    /// "M", "T", …
    var initial: String {
        Calendar.current.veryShortWeekdaySymbols[Self.ordered.firstIndex(of: self) ?? 0]
    }
}

/// A repeat rule without the device's calendar, locale and time zone, for syncing between
/// devices (so two phones with different settings don't keep re-uploading the same rule).
nonisolated struct PortableRepeatRule: Codable, Hashable, Sendable {
    var frequency: String
    var interval: Int
    /// "mon", or "-1fri" for the last Friday.
    var weekdays: [String]?
    var daysOfTheMonth: [Int]?
    var months: [Int]?
    var end: Date?

    init(_ rule: RepeatRule) {
        frequency = switch rule.frequency {
        case .minutely: "minutely"
        case .hourly: "hourly"
        case .daily: "daily"
        case .weekly: "weekly"
        case .monthly: "monthly"
        case .yearly: "yearly"
        @unknown default: "daily"
        }
        interval = rule.interval
        let days = rule.weekdays.map { weekday -> String in
            switch weekday {
            case .every(let day): return day.rawValue
            case .nth(let n, let day): return "\(n)\(day.rawValue)"
            @unknown default: return ""
            }
        }
        weekdays = days.isEmpty ? nil : days
        daysOfTheMonth = rule.daysOfTheMonth.isEmpty ? nil : rule.daysOfTheMonth
        months = rule.months.isEmpty ? nil : rule.months.map(\.index)
        end = rule.endDate
    }

    var rule: RepeatRule {
        let frequency: RepeatRule.Frequency = switch self.frequency {
        case "minutely": .minutely
        case "hourly": .hourly
        case "weekly": .weekly
        case "monthly": .monthly
        case "yearly": .yearly
        default: .daily
        }
        let weekdays = (self.weekdays ?? []).compactMap { text -> RepeatRule.Weekday? in
            let digits = text.prefix { $0 == "-" || $0.isNumber }
            guard let day = Locale.Weekday(rawValue: String(text.dropFirst(digits.count))) else { return nil }
            return digits.isEmpty ? .every(day) : Int(digits).map { .nth($0, day) }
        }
        return RepeatRule(
            calendar: .current,
            frequency: frequency,
            interval: max(1, interval),
            end: end.map { .afterDate($0) } ?? .never,
            months: (months ?? []).map { RepeatRule.Month($0) },
            daysOfTheMonth: daysOfTheMonth ?? [],
            weekdays: weekdays
        )
    }
}
