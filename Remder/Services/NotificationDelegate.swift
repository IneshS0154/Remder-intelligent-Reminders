import Foundation
import Observation
import SwiftData
import UserNotifications

@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    /// Set when a reminder fires or its notification is tapped; the list shows the due screen for it.
    var pendingReminderID: UUID?

    private init() {}
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if let id = reminderID(from: notification) {
            DeepLinkRouter.shared.pendingReminderID = id
        }
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let id = reminderID(from: response.notification) else { return }

        switch response.actionIdentifier {
        case NotificationManager.completeActionID:
            perform(on: id) { NotificationManager.shared.complete($0) }
        case UNNotificationDefaultActionIdentifier:
            DeepLinkRouter.shared.pendingReminderID = id
        case let action:
            if let option = SnoozeOption(actionID: action) {
                perform(on: id) { NotificationManager.shared.snooze($0, option: option) }
            }
        }
    }

    private func reminderID(from notification: UNNotification) -> UUID? {
        guard let idString = notification.request.content.userInfo["reminderID"] as? String else { return nil }
        return UUID(uuidString: idString)
    }

    private func perform(on id: UUID, _ action: (Reminder) -> Void) {
        ReminderIntentHandler.perform(on: id, action)
    }
}
