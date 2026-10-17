import Foundation
import SwiftData

/// Applies reminder actions that arrive from outside the UI: notification buttons and
/// the Live Activity's "Done" button (`CompleteReminderIntent`).
enum ReminderIntentHandler {
    static func complete(reminderID: String) async {
        guard let id = UUID(uuidString: reminderID) else { return }
        let found = perform(on: id) { NotificationManager.shared.complete($0) }
        if !found {
            // The reminder was deleted; don't leave its countdown behind.
            LiveActivityManager.shared.end(reminderID: id)
        }
    }

    @discardableResult
    static func perform(on id: UUID, _ action: (Reminder) -> Void) -> Bool {
        let context = RemderApp.sharedContainer.mainContext
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == id })
        guard let reminder = try? context.fetch(descriptor).first else { return false }
        action(reminder)
        try? context.save()
        return true
    }
}
