import Foundation

/// Stub so the shared `CompleteReminderIntent` compiles here. Live Activity intents run in the
/// app's process, where the real `ReminderIntentHandler` does the work.
enum ReminderIntentHandler {
    static func complete(reminderID: String) async {}
}
