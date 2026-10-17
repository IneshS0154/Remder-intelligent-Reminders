#if os(iOS)
import AppIntents
import Foundation

/// "Done" button on the Live Activity. Live Activity intents always run in the app's process,
/// so the widget extension only needs a stub `ReminderIntentHandler`.
struct CompleteReminderIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Complete Reminder"
    static let isDiscoverable = false

    @Parameter(title: "Reminder ID")
    var reminderID: String

    init() {}

    init(reminderID: String) {
        self.reminderID = reminderID
    }

    func perform() async throws -> some IntentResult {
        await ReminderIntentHandler.complete(reminderID: reminderID)
        return .result()
    }
}
#endif
