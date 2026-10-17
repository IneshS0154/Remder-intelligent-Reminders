import Foundation
import Testing
@testable import Remder

@MainActor
@Suite("Custom repeats")
struct RepeatRuleTests {
    let calendar = Calendar.current

    @Test("Every 2 weeks on Mon and Wed starts on the first matching day and keeps its rhythm")
    func everyTwoWeeksOnMondayAndWednesday() {
        let rule = RepeatRule(calendar: calendar, frequency: .weekly, interval: 2, weekdays: [.every(.monday), .every(.wednesday)])
        let item = reminder(due: date(2026, 9, 24), rule: rule)  // a Thursday
        item.snapToRepeatRule()

        #expect(item.dueDate == date(2026, 10, 5))
        #expect(item.nextOccurrence(after: date(2026, 10, 5)) == date(2026, 10, 7))
        #expect(item.nextOccurrence(after: date(2026, 10, 7)) == date(2026, 10, 19))
    }

    @Test("Last Friday of every month")
    func lastFriday() {
        let rule = RepeatRule(calendar: calendar, frequency: .monthly, weekdays: [.nth(-1, .friday)])
        let item = reminder(due: date(2026, 9, 24), rule: rule)
        item.snapToRepeatRule()

        #expect(item.dueDate == date(2026, 9, 25))
        #expect(item.nextOccurrence(after: item.dueDate) == date(2026, 10, 30))
        #expect(item.nextOccurrence(after: date(2026, 10, 30)) == date(2026, 11, 27))
    }

    @Test("Weekdays skip the weekend")
    func weekdays() {
        let item = reminder(due: date(2026, 9, 26, 8), rule: .weekdays())  // a Saturday
        item.snapToRepeatRule()

        #expect(item.dueDate == date(2026, 9, 28, 8))
        #expect(item.nextOccurrence(after: date(2026, 10, 2, 8)) == date(2026, 10, 5, 8))
    }

    @Test("A repeat with an end date stops")
    func endDate() {
        let rule = RepeatRule(calendar: calendar, frequency: .daily, end: .afterDate(date(2026, 9, 26, 23, 59)))
        let item = reminder(due: date(2026, 9, 24), rule: rule)

        #expect(item.nextOccurrence(after: date(2026, 9, 25)) == date(2026, 9, 26))
        #expect(item.nextOccurrence(after: date(2026, 9, 26)) == nil)
    }

    @Test("Monthly on the 31st skips shorter months instead of drifting")
    func monthlyOnThe31st() {
        let rule = RepeatRule(calendar: calendar, frequency: .monthly, daysOfTheMonth: [31])
        let item = reminder(due: date(2026, 8, 31), rule: rule)
        #expect(item.nextOccurrence(after: date(2026, 8, 31)) == date(2026, 10, 31))
    }

    @Test("Plain daily, weekly and monthly rules are stored as the simple presets")
    func presetsStayPresets() {
        let item = reminder(due: date(2026, 9, 24))
        item.repeatRule = .daily(calendar: calendar)
        #expect(item.repeatFrequency == .daily)
        #expect(item.repeatRuleData == nil)

        item.repeatRule = .everyTwoWeeks()
        #expect(item.repeatFrequency == .custom)
        #expect(item.repeatRuleData != nil)

        item.repeatRule = nil
        #expect(item.repeatFrequency == .none)
        #expect(item.repeatRuleData == nil)
    }

    @Test("Rules survive the round trip through sync")
    func portableRoundTrip() {
        let rules: [RepeatRule] = [
            RepeatRule(calendar: calendar, frequency: .monthly, interval: 2, end: .afterDate(date(2027, 1, 1)), weekdays: [.nth(-1, .friday)]),
            RepeatRule(calendar: calendar, frequency: .weekly, interval: 3, weekdays: [.every(.tuesday), .every(.saturday)]),
            RepeatRule(calendar: calendar, frequency: .monthly, daysOfTheMonth: [15]),
            .yearly(calendar: calendar),
        ]
        for rule in rules {
            let portable = PortableRepeatRule(rule)
            #expect(PortableRepeatRule(portable.rule) == portable)
            let start = date(2026, 9, 24)
            #expect(Array(portable.rule.recurrences(of: start).prefix(5)) == Array(rule.recurrences(of: start).prefix(5)))
        }
    }

    @Test("Summaries read naturally", arguments: [
        (RepeatRule(calendar: .current, frequency: .weekly, interval: 2, weekdays: [.every(.monday), .every(.wednesday)]), "Every 2 weeks on Mon, Wed"),
        (RepeatRule.weekdays(), "Weekdays"),
        (RepeatRule(calendar: .current, frequency: .monthly, weekdays: [.nth(-1, .friday)]), "Last Friday of every month"),
        (RepeatRule(calendar: .current, frequency: .daily, interval: 3), "Every 3 days"),
        (RepeatRule(calendar: .current, frequency: .monthly, daysOfTheMonth: [1]), "Monthly on the 1st"),
        (RepeatRule.yearly(calendar: .current), "Yearly"),
    ])
    func summaries(rule: RepeatRule, expected: String) {
        #expect(rule.summary == expected)
    }

    @Test("The Repeat menu recognizes its own choices")
    func repeatChoices() {
        for choice in RepeatChoice.allCases where choice != .custom {
            #expect(RepeatChoice(choice.rule) == choice)
        }
        #expect(RepeatChoice(RepeatRule(calendar: calendar, frequency: .daily, interval: 3)) == .custom)
    }
}
