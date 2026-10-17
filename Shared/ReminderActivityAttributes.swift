#if os(iOS)
import ActivityKit
import Foundation

/// Live Activity shown in the Dynamic Island and on the Lock Screen ahead of a reminder.
/// Compiled into both the app and the widget extension.
nonisolated struct ReminderActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        /// When the reminder is due; changes when the reminder is snoozed.
        var dueDate: Date
        /// When the countdown began (due − lead time); drives the progress bar.
        var startDate: Date?
    }

    var reminderID: String
    var title: String
    var notes: String?
    /// 0 = low, 1 = medium, 2 = high (mirrors `Priority`, which only exists in the app).
    var priority: Int
    var category: String?
}
#endif
