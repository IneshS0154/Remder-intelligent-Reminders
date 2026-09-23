import SwiftUI
import SwiftData
import UserNotifications

@main
struct RemderApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ReminderListView()
        }
        .modelContainer(for: Reminder.self)
    }
}
