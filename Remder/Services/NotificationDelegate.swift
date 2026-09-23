import Foundation
import Observation
import UserNotifications

@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

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
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if let idString = response.notification.request.content.userInfo["reminderID"] as? String,
           let id = UUID(uuidString: idString) {
            DeepLinkRouter.shared.pendingReminderID = id
        }
    }
}
