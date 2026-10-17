import Foundation
import FoundationModels
import SwiftData
import UIKit

/// Turns a line of text into a saved reminder: the offline `QuickAddParser`, refined by
/// Apple Intelligence on devices that support it. Used by the quick add sheet and by Siri.
enum QuickAdd {
    /// The full pipeline for one line of text.
    static func interpret(_ text: String, categories: [String], now: Date = .now) async -> ParsedReminder {
        let parsed = QuickAddParser.parse(text, categories: categories, now: now)
        guard AIQuickAdd.isEnabled,
              let ai = try? await AIQuickAdd.parse(text, categories: categories, now: now)
        else { return parsed }
        return merge(parsed: parsed, ai: ai)
    }

    /// Explicit syntax (#tag, !high, "alarm", "10 min before") always wins. Apple Intelligence
    /// supplies a cleaner title and understands looser phrasing like "after work on Friday".
    static func merge(parsed: ParsedReminder, ai: ParsedReminder) -> ParsedReminder {
        var result = parsed
        if !ai.title.isEmpty { result.title = ai.title }
        if ai.hasExplicitDate {
            result.dueDate = ai.dueDate
            result.hasExplicitDate = true
        }
        if result.repeatFrequency == .none, result.repeatRule == nil {
            result.repeatFrequency = ai.repeatFrequency
            result.repeatRule = ai.repeatRule
        }
        if result.location == nil { result.location = ai.location }
        if result.priority == nil { result.priority = ai.priority }
        if result.category == nil, let category = ai.category {
            result.category = category
            result.isNewCategory = false
        }
        result.alarm = parsed.alarm || ai.alarm
        return result
    }

    /// Creates the reminder (and a new category if one was typed) and schedules its alerts.
    @discardableResult
    static func save(_ parsed: ParsedReminder, categories: [ReminderCategory], in context: ModelContext) -> Reminder {
        let category = parsed.category ?? ""
        if !category.isEmpty, !categories.contains(where: { $0.name == category }) {
            let order = (categories.map(\.sortOrder).max() ?? -1) + 1
            context.insert(ReminderCategory(name: category, color: CategoryStore.nextColor(avoiding: categories), sortOrder: order))
        }

        let reminder = Reminder(
            title: parsed.title,
            dueDate: parsed.dueDate,
            priority: parsed.priority ?? AppSettings.defaultPriority,
            category: category,
            liveActivityLeadMinutes: parsed.leadMinutes ?? AppSettings.defaultLeadMinutes
        )
        context.insert(reminder)
        reminder.alarmEnabled = parsed.alarm || AppSettings.defaultAlarm
        reminder.nagIntervalMinutes = AppSettings.defaultNagMinutes
        if let location = parsed.location {
            // Location reminders go off at the place, not at a time.
            reminder.location = location
            reminder.alarmEnabled = false
            reminder.liveActivityLeadMinutes = 0
            reminder.nagIntervalMinutes = 0
        } else {
            reminder.repeatRule = parsed.effectiveRepeatRule
            reminder.snapToRepeatRule()
        }
        try? context.save()
        NotificationManager.shared.reschedule(for: reminder)
        if reminder.alarmEnabled {
            Task {
                if await AlarmScheduler.shared.requestAuthorization() {
                    AlarmScheduler.shared.sync(reminder)
                }
            }
        }
        return reminder
    }
}

// MARK: - Apple Intelligence

/// Reads a reminder out of loosely written text with Apple's on-device language model.
/// The model only extracts words ("friday 17:00"); `QuickAddParser` turns them into a date,
/// because the model is unreliable at date arithmetic.
enum AIQuickAdd {
    /// The device supports Apple Intelligence and it's turned on (iPhone 15 Pro or later).
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    /// Available and not switched off in Settings.
    static var isEnabled: Bool { isAvailable && AppSettings.useAppleIntelligence }

    /// Why it can't be used, for Settings.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "This iPhone doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in the Settings app to use it."
        case .unavailable(.modelNotReady): return "Apple Intelligence is still getting ready. Try again later."
        case .unavailable: return "Apple Intelligence isn't available right now."
        }
    }

    static func parse(_ text: String, categories: [String], now: Date) async throws -> ParsedReminder {
        let session = LanguageModelSession(instructions: instructions(categories: categories, now: now))
        let extraction = try await session.respond(
            to: text,
            generating: ReminderExtraction.self,
            options: GenerationOptions(samplingMode: .greedy)
        ).content

        // The model sometimes invents a time for text without one ("Call mom"); ignore it then.
        let when = mentionsTime(text) ? extraction.when.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        var result = when.isEmpty
            ? ParsedReminder(dueDate: QuickAddParser.parse("", now: now).dueDate)
            : QuickAddParser.parse(when, categories: categories, now: now)
        let title = extraction.title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        result.title = title.prefix(1).uppercased() + title.dropFirst()
        switch extraction.repeats {
        case .none: break
        case .daily: result.repeatFrequency = .daily
        case .weekdays: result.repeatRule = .weekdays()
        case .weekly: result.repeatFrequency = .weekly
        case .everyTwoWeeks: result.repeatRule = .everyTwoWeeks()
        case .monthly: result.repeatFrequency = .monthly
        case .yearly: result.repeatRule = .yearly(calendar: .current)
        }
        switch extraction.priority {
        case .none: result.priority = nil
        case .low: result.priority = .low
        case .medium: result.priority = .medium
        case .high: result.priority = .high
        }
        // Only existing categories; new ones are created by typing #name.
        result.category = categories.first { $0.localizedCaseInsensitiveCompare(extraction.category) == .orderedSame }
        result.isNewCategory = false
        result.alarm = extraction.alarm
        result.leadMinutes = nil
        return result
    }

    /// Whether the text says anything about when: a number, or a day or time-of-day word.
    static func mentionsTime(_ text: String) -> Bool {
        let words = #"\d|\b(today|tonight|tomorrow|tmrw|yesterday|morning|afternoon|evening|night|noon|midnight|lunch|dinner|breakfast|weekend|week|month|year|after work|before work|later|soon|next|this|monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec|january|february|march|april|june|july|august|september|october|november|december|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|half|quarter|hour|hours|minute|minutes|daily|weekly|monthly|every)\b"#
        return text.range(of: words, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func instructions(categories: [String], now: Date) -> String {
        let english = Locale(identifier: "en_US")
        let today = now.formatted(Date.FormatStyle(locale: english).weekday(.wide).month(.wide).day().year())
        let time = now.formatted(Date.FormatStyle(locale: english).hour(.twoDigits(amPM: .omitted)).minute())
        let categoryList = categories.isEmpty ? "(none)" : categories.joined(separator: ", ")
        return """
        You turn a note someone typed into a reminder. It is now \(today), \(time).
        - title: only the task, short, in sentence case. Leave out filler like "remind me to" or "don't forget", \
        the day and time, and any words starting with # or !.
        - when: copy the day the person named (today, tomorrow, a weekday like "friday", or a date like "sep 30") \
        and add a 24-hour time. Vague times: morning 09:00, noon 12:00, afternoon 15:00, after work 17:00, \
        evening 19:00, tonight 20:00. For relative times write "in 20 minutes" or "in 2 hours". \
        Never work out calendar dates yourself. If the note mentions no day and no time, `when` must be empty; never guess one.
        - category: the best fit from this list, or empty if none fits: \(categoryList).
        - priority: high only for urgent or important things, low for things that can wait, otherwise none.
        """
    }
}

@Generable
struct ReminderExtraction {
    @Guide(description: "The task, short, sentence case, e.g. 'Pick up dry cleaning'")
    var title: String
    @Guide(description: "Day and 24-hour time as words, e.g. 'friday 17:00', 'tomorrow 09:00', 'in 2 hours', or empty")
    var when: String
    var repeats: ExtractedRepeat
    var priority: ExtractedPriority
    @Guide(description: "A category name from the given list, or empty")
    var category: String
    @Guide(description: "True only if an alarm or wake-up is asked for")
    var alarm: Bool
}

@Generable
enum ExtractedRepeat {
    case none, daily, weekdays, weekly, everyTwoWeeks, monthly, yearly
}

@Generable
enum ExtractedPriority {
    case none, low, medium, high
}
