import Foundation
import SwiftData
@testable import Remder

/// A local date, e.g. `date(2026, 9, 24, 9)` for Thu 24 Sep 2026 at 9:00.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// A throwaway in-memory database for tests that need relationships (completions).
@MainActor
func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: SharedStore.schema,
        configurations: ModelConfiguration(schema: SharedStore.schema, isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

@MainActor
func reminder(_ title: String = "Test", due: Date, rule: RepeatRule? = nil, in context: ModelContext? = nil) -> Reminder {
    let reminder = Reminder(title: title, dueDate: due)
    context?.insert(reminder)
    reminder.repeatRule = rule
    return reminder
}
