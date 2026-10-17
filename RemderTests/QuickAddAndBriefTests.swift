import Foundation
import Testing
@testable import Remder

@MainActor
@Suite("Quick add: repeats and places", .serialized)
struct QuickAddRepeatTests {
    /// Thursday 24 Sep 2026, 2 PM.
    let now = date(2026, 9, 24, 14)

    @Test("Repeat phrases", arguments: [
        ("Standup every weekday 9am", "Standup", "Weekdays"),
        ("Water plants every 3 days", "Water plants", "Every 3 days"),
        ("Team sync every mon and wed 10am", "Team sync", "Weekly on Mon, Wed"),
        ("Book club every last thursday 7pm", "Book club", "Last Thursday of every month"),
        ("Pay rent every 1st", "Pay rent", "Monthly on the 1st"),
        ("Anniversary dinner every year", "Anniversary dinner", "Yearly"),
        ("Clean the fridge every other week", "Clean the fridge", "Every 2 weeks"),
        ("Gym every day 7am", "Gym", "Daily"),
    ])
    func repeatPhrases(text: String, title: String, summary: String) {
        let parsed = QuickAddParser.parse(text, now: now)
        #expect(parsed.title == title)
        #expect(parsed.repeatLabel == summary)
    }

    @Test("“When I get home” uses the saved Home place")
    func places() {
        let home = ReminderLocation(name: "Home", latitude: 6.9271, longitude: 79.8612)
        AppSettings.setPlace(.home, to: home)
        defer { AppSettings.setPlace(.home, to: nil) }

        let arriving = QuickAddParser.parse("Take out the trash when I get home", now: now)
        #expect(arriving.title == "Take out the trash")
        #expect(arriving.location?.name == "Home")
        #expect(arriving.location?.trigger == .arriving)

        let leaving = QuickAddParser.parse("Lock the door when I leave home", now: now)
        #expect(leaving.title == "Lock the door")
        #expect(leaving.location?.trigger == .leaving)
    }

    @Test("Without a saved place the words stay in the title")
    func unsavedPlace() {
        AppSettings.setPlace(.work, to: nil)
        let parsed = QuickAddParser.parse("Call Sam when I get to work", now: now)
        #expect(parsed.location == nil)
    }
}

@Suite("Snooze choices")
struct SnoozeTests {
    @Test("This evening is 6 PM, or 3 hours later once it's evening")
    func evening() {
        #expect(SnoozeOption.evening.date(from: date(2026, 9, 24, 14), minutes: 10) == date(2026, 9, 24, 18))
        #expect(SnoozeOption.evening.date(from: date(2026, 9, 24, 17, 45), minutes: 10) == date(2026, 9, 24, 20, 45))
        #expect(SnoozeOption.evening.date(from: date(2026, 9, 24, 19), minutes: 10) == date(2026, 9, 24, 22))
    }

    @Test("Tomorrow morning is 9 AM the next day, or today in the small hours")
    func tomorrowMorning() {
        #expect(SnoozeOption.tomorrowMorning.date(from: date(2026, 9, 24, 23), minutes: 10) == date(2026, 9, 25, 9))
        #expect(SnoozeOption.tomorrowMorning.date(from: date(2026, 9, 24, 2), minutes: 10) == date(2026, 9, 24, 9))
    }

    @Test("Minutes and one hour")
    func fixedLengths() {
        let now = date(2026, 9, 24, 14)
        #expect(SnoozeOption.minutes.date(from: now, minutes: 15) == date(2026, 9, 24, 14, 15))
        #expect(SnoozeOption.hour.date(from: now, minutes: 15) == date(2026, 9, 24, 15))
    }

    @Test("Notification action IDs round-trip, and the original one still works")
    func actionIDs() {
        for option in SnoozeOption.allCases {
            #expect(SnoozeOption(actionID: option.actionID) == option)
        }
        #expect(SnoozeOption(actionID: "SNOOZE") == .minutes)
    }
}

@MainActor
@Suite("Daily brief")
struct BriefTests {
    let today = date(2026, 9, 24, 0)

    @Test("Morning summary lists today's reminders, soonest first")
    func morning() {
        let items = [
            reminder("Call mom", due: date(2026, 9, 24, 17)),
            reminder("Gym", due: date(2026, 9, 24, 7)),
            reminder("Tomorrow thing", due: date(2026, 9, 25, 10)),
            reminder("Vitamins", due: date(2026, 9, 20, 21), rule: .daily(calendar: .current)),
        ]
        let text = BriefScheduler.summary(.morning, reminders: items, day: today, at: date(2026, 9, 24, 8))
        #expect(text?.title == "Good morning")
        #expect(text?.body.hasPrefix("3 reminders today: Gym") == true)
        #expect(text?.body.contains("Vitamins") == true)
        #expect(text?.body.contains("Tomorrow thing") == false)
    }

    @Test("Morning summary mentions overdue reminders")
    func overdue() {
        let items = [reminder("Old task", due: date(2026, 9, 22, 10))]
        let text = BriefScheduler.summary(.morning, reminders: items, day: today, at: date(2026, 9, 24, 8))
        #expect(text?.body == "Nothing new today. 1 overdue.")
    }

    @Test("Nothing today means no brief at all")
    func empty() {
        let items = [reminder("Later", due: date(2026, 9, 30))]
        #expect(BriefScheduler.summary(.morning, reminders: items, day: today, at: date(2026, 9, 24, 8)) == nil)
        #expect(BriefScheduler.summary(.evening, reminders: items, day: today, at: date(2026, 9, 24, 20)) == nil)
    }

    @Test("Evening check-in lists what's still open")
    func evening() {
        let items = [
            reminder("Pay rent", due: date(2026, 9, 24, 10)),
            reminder("Call mom", due: date(2026, 9, 24, 17)),
        ]
        let text = BriefScheduler.summary(.evening, reminders: items, day: today, at: date(2026, 9, 24, 20))
        #expect(text?.body == "2 still to do today: Pay rent and Call mom.")
    }

    @Test("A custom repeat counts only on its days")
    func customRepeatDays() {
        let rule = RepeatRule(calendar: .current, frequency: .weekly, weekdays: [.every(.monday), .every(.wednesday)])
        let item = reminder("Swim", due: date(2026, 9, 21, 6), rule: rule)
        let thursday = BriefScheduler.occurrences(of: item, in: Calendar.current.dateInterval(of: .day, for: date(2026, 9, 24))!)
        let monday = BriefScheduler.occurrences(of: item, in: Calendar.current.dateInterval(of: .day, for: date(2026, 9, 28))!)
        #expect(thursday.isEmpty)
        #expect(monday == [date(2026, 9, 28, 6)])
    }
}

@MainActor
@Suite("Streaks on custom repeats")
struct CustomStreakTests {
    @Test("Every 2 days, all done: the streak counts each occurrence")
    func everyOtherDay() throws {
        let context = try makeContext()
        let rule = RepeatRule(calendar: .current, frequency: .daily, interval: 2)
        let item = reminder("Stretch", due: date(2026, 9, 26), rule: rule, in: context)
        item.createdDate = date(2026, 9, 14, 8)
        for day in [14, 16, 18, 20, 22, 24] {
            item.completions.append(Completion(occurrenceDate: date(2026, 9, day), completedAt: date(2026, 9, day, 10)))
        }

        let stats = StreakCalculator.stats(for: item, now: date(2026, 9, 24, 12))
        #expect(stats.current == 6)
        #expect(stats.best == 6)
        #expect(stats.totalCompleted == 6)
    }

    @Test("A missed day breaks the streak")
    func missed() throws {
        let context = try makeContext()
        let rule = RepeatRule(calendar: .current, frequency: .daily, interval: 2)
        let item = reminder("Stretch", due: date(2026, 9, 26), rule: rule, in: context)
        item.createdDate = date(2026, 9, 14, 8)
        for day in [14, 16, 20, 22, 24] {  // missed the 18th
            item.completions.append(Completion(occurrenceDate: date(2026, 9, day), completedAt: date(2026, 9, day, 10)))
        }

        let stats = StreakCalculator.stats(for: item, now: date(2026, 9, 24, 12))
        #expect(stats.current == 3)
        #expect(stats.best == 3)
    }
}
