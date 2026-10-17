import Foundation

/// What quick add understood from a line like "Call mom tomorrow 5pm #Work !high".
struct ParsedReminder: Identifiable, Equatable {
    var id = UUID()
    var title: String = ""
    var dueDate: Date
    /// False when no date or time was typed and `dueDate` is the default.
    var hasExplicitDate = false
    var repeatFrequency: RepeatFrequency = .none
    /// A repeat the presets can't express ("every weekday", "every 2 weeks"); wins over `repeatFrequency`.
    var repeatRule: RepeatRule?
    /// "When I get home": a location reminder instead of one at a time.
    var location: ReminderLocation?

    /// The repeat as a rule, whichever way it was set.
    var effectiveRepeatRule: RepeatRule? { repeatRule ?? repeatFrequency.presetRule }

    /// "Daily", "Every 2 weeks on Mon".
    var repeatLabel: String? {
        if let repeatRule { return repeatRule.summary }
        return repeatFrequency == .none ? nil : repeatFrequency.label
    }
    var priority: Priority?
    /// Category name as typed (matched case-insensitively to an existing one when possible).
    var category: String?
    /// True when `category` doesn't exist yet; it's created on save.
    var isNewCategory = false
    var alarm = false
    var leadMinutes: Int?
}

/// Offline parser for quick add. Understands:
/// - dates/times via NSDataDetector ("tomorrow 5pm", "next Friday at 9", "in 2 hours", "Sep 30")
/// - repeats ("every day", "daily", "every Monday", "weekly", "monthly")
/// - #category, !high / !med / !low (or !!! / !! / !), "alarm" or ⏰, "10 min before"
enum QuickAddParser {
    static func parse(_ input: String, categories: [String] = [], now: Date = .now) -> ParsedReminder {
        var text = " " + input + " "
        var result = ParsedReminder(dueDate: defaultDate(now: now))

        // Priority.
        let priorities: [(String, Priority)] = [
            (#"(?i)(?<!\S)(!high|!h|!!!)(?!\S)"#, .high),
            (#"(?i)(?<!\S)(!medium|!med|!m|!!)(?!\S)"#, .medium),
            (#"(?i)(?<!\S)(!low|!l|!)(?!\S)"#, .low),
        ]
        for (pattern, priority) in priorities where take(pattern, from: &text) != nil {
            result.priority = priority
            break
        }

        // Category.
        if let tag = take(#"(?<!\S)#([\p{L}\p{N}_-]+)"#, from: &text, group: 1) {
            if let existing = categories.first(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) {
                result.category = existing
            } else {
                result.category = tag
                result.isNewCategory = true
            }
        }

        // Alarm.
        if take(#"(?i)(?<!\S)(alarm|⏰)(?!\S)"#, from: &text) != nil {
            result.alarm = true
        }

        // Live Activity lead: "10 min before", "1 hour before".
        if let match = take(#"(?i)\b(\d{1,3})\s*(m|min|mins|minutes?|h|hr|hrs|hours?)\s+before\b"#, from: &text, groups: [1, 2]),
           let amount = Int(match[0]) {
            let minutes = match[1].lowercased().hasPrefix("h") ? amount * 60 : amount
            // Snap to the options the form offers.
            result.leadMinutes = [5, 10, 15, 30, 60].min { abs($0 - minutes) < abs($1 - minutes) }
        }

        // Places: "when I get home", "when I leave work" (uses the places saved in Settings).
        if let match = take(#"(?i)\b(?:when|once|as soon as)\s+i\s*(?:'m|am)?\s*(get|arrive|reach|leave|at)\s+(?:to\s+|at\s+|back\s+)?(home|work)\b"#, from: &text, groups: [1, 2]),
           let place = AppSettings.Place.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(match[1]) == .orderedSame }),
           var location = AppSettings.place(place) {
            location.trigger = match[0].lowercased() == "leave" ? .leaving : .arriving
            result.location = location
        }

        // Repeats. "every Monday" keeps "Monday" so the date detector can use it.
        let dayNames = #"(?:mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)(?:day|sday|nesday|rsday|urday)?"#
        let calendar = Calendar.current
        if take(#"(?i)\b(?:every\s+weekdays?|on\s+weekdays|weekdays)\b"#, from: &text) != nil {
            result.repeatRule = .weekdays(calendar: calendar)
        } else if take(#"(?i)\b(?:every\s+weekends?|on\s+weekends|weekends)\b"#, from: &text) != nil {
            result.repeatRule = RepeatRule(calendar: calendar, frequency: .weekly, weekdays: [.every(.saturday), .every(.sunday)])
        } else if let match = take(#"(?i)\bevery\s+(\d{1,3}|other)\s+(days?|weeks?|months?|years?)\b"#, from: &text, groups: [1, 2]) {
            let interval = match[0].lowercased() == "other" ? 2 : max(1, Int(match[0]) ?? 1)
            let unit = match[1].lowercased()
            let frequency: RepeatRule.Frequency = unit.hasPrefix("d") ? .daily : unit.hasPrefix("w") ? .weekly : unit.hasPrefix("m") ? .monthly : .yearly
            result.repeatRule = RepeatRule(calendar: calendar, frequency: frequency, interval: interval)
        } else if let match = take(#"(?i)\bevery\s+(first|1st|second|2nd|third|3rd|fourth|4th|last)\s+("# + dayNames + #")(?:\s+of\s+(?:the|every)\s+month)?\b"#, from: &text, groups: [1, 2]),
                  let weekday = Self.weekday(named: match[1]) {
            let position = ["first": 1, "1st": 1, "second": 2, "2nd": 2, "third": 3, "3rd": 3, "fourth": 4, "4th": 4, "last": -1][match[0].lowercased()] ?? 1
            result.repeatRule = RepeatRule(calendar: calendar, frequency: .monthly, weekdays: [.nth(position, weekday)])
        } else if let match = take(#"(?i)\b(?:every|on\s+the)\s+(\d{1,2})(?:st|nd|rd|th)(?:\s+of\s+(?:the|every)\s+month)?\b"#, from: &text, group: 1),
                  let day = Int(match), (1...31).contains(day) {
            result.repeatRule = RepeatRule(calendar: calendar, frequency: .monthly, daysOfTheMonth: [day])
        } else if let match = take(#"(?i)\bevery\s+("# + dayNames + #"(?:\s*(?:,|and|&)\s*"# + dayNames + #")+)\b"#, from: &text, group: 1) {
            // "every mon and wed", "every tuesday, thursday & saturday"
            let days = match.components(separatedBy: CharacterSet(charactersIn: ",&").union(.whitespaces))
                .filter { !$0.isEmpty && $0.lowercased() != "and" }
                .compactMap(Self.weekday(named:))
            if days.count > 1 {
                result.repeatRule = RepeatRule(calendar: calendar, frequency: .weekly, weekdays: days.map { .every($0) })
            }
        } else if take(#"(?i)\b(every\s*year|yearly|annually)\b"#, from: &text) != nil {
            result.repeatRule = .yearly(calendar: calendar)
        } else if take(#"(?i)\b(every\s*day|everyday|daily)\b"#, from: &text) != nil {
            result.repeatFrequency = .daily
        } else if let weekday = take(#"(?i)\bevery\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#, from: &text, group: 1) {
            result.repeatFrequency = .weekly
            text += " \(weekday) "
        } else if take(#"(?i)\b(every\s*week|weekly)\b"#, from: &text) != nil {
            result.repeatFrequency = .weekly
        } else if take(#"(?i)\b(every\s*month|monthly)\b"#, from: &text) != nil {
            result.repeatFrequency = .monthly
        }

        // Date and time. Relative offsets first ("in 2 hours"), which the detector doesn't handle.
        if let match = take(#"(?i)\bin\s+(\d{1,4})\s*(minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|w)\b"#, from: &text, groups: [1, 2]),
           let amount = Int(match[0]) {
            let unit = match[1].lowercased()
            let seconds: TimeInterval = unit.hasPrefix("m") ? 60 : unit.hasPrefix("h") ? 3600 : unit.hasPrefix("d") ? 86_400 : 604_800
            result.dueDate = now.addingTimeInterval(Double(amount) * seconds)
            result.hasExplicitDate = true
        } else if let (date, matchedText) = detectDate(in: &text, now: now) {
            result.dueDate = resolve(date, matchedText: matchedText, now: now)
            result.hasExplicitDate = true
        }

        result.title = cleanTitle(text)
        return result
    }

    /// "mon", "Monday", "thurs" → the weekday.
    nonisolated static func weekday(named name: String) -> Locale.Weekday? {
        let prefixes: [(String, Locale.Weekday)] = [
            ("mon", .monday), ("tue", .tuesday), ("wed", .wednesday), ("thu", .thursday),
            ("fri", .friday), ("sat", .saturday), ("sun", .sunday),
        ]
        let lower = name.lowercased()
        return prefixes.first { lower.hasPrefix($0.0) }?.1
    }

    // MARK: - Dates

    private static func detectDate(in text: inout String, now: Date) -> (Date, String)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range),
              let date = match.date,
              let swiftRange = Range(match.range, in: text) else { return nil }
        let matched = String(text[swiftRange])
        text.replaceSubrange(swiftRange, with: " ")
        return (date, matched)
    }

    /// Fills in a sensible time when only a day was typed, and rolls a time that has already
    /// passed today over to tomorrow when no day was given.
    private static func resolve(_ date: Date, matchedText: String, now: Date) -> Date {
        let calendar = Calendar.current
        let lower = matchedText.lowercased()
        let hasTime = lower.range(
            of: #"\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)|\d{1,2}:\d{2}|\bat\s+\d{1,2}\b|o'clock|noon|midnight|morning|afternoon|evening|tonight|night"#,
            options: .regularExpression
        ) != nil
        let hasDay = lower.range(of: #"today|tomorrow|tonight|mon|tue|wed|thu|fri|sat|sun|week|month|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|/|\bin\b"#,
                                 options: .regularExpression) != nil

        var result = date
        if !hasTime {
            // Day only: 9 AM that day, or the next hour if that's already past.
            result = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
            if result <= now { result = nextWholeHour(after: now) }
        } else if !hasDay, result <= now {
            result = calendar.date(byAdding: .day, value: 1, to: result) ?? result
        }
        return result
    }

    private static func defaultDate(now: Date) -> Date {
        nextWholeHour(after: now)
    }

    private static func nextWholeHour(after date: Date) -> Date {
        let calendar = Calendar.current
        let hourStart = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? date
    }

    // MARK: - Helpers

    /// Removes the first match of `pattern` from `text`; returns the whole match (or `group`).
    @discardableResult
    private static func take(_ pattern: String, from text: inout String, group: Int = 0) -> String? {
        take(pattern, from: &text, groups: [group])?.first
    }

    private static func take(_ pattern: String, from text: inout String, groups: [Int]) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let whole = Range(match.range, in: text) else { return nil }
        let captured = groups.compactMap { index -> String? in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
        text.replaceSubrange(whole, with: " ")
        return captured
    }

    /// Tidies what's left into the title: collapses spaces and drops dangling joiners like "at".
    private static func cleanTitle(_ text: String) -> String {
        var title = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;-")))
        let joiners = #"(?i)\s+(at|on|by|in|for|next|this|every|when|and)$"#
        while let range = title.range(of: joiners, options: .regularExpression) {
            title.removeSubrange(range)
        }
        return title
    }
}
