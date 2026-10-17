#if os(iOS)
import AlarmKit
import Foundation

/// Extra data carried by a reminder's alarm, so the snooze countdown can show which reminder it is.
/// Compiled into both the app and the widget extension.
nonisolated struct ReminderAlarmMetadata: AlarmMetadata {
    var reminderID: String
    var title: String
}
#endif
