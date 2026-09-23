import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(for reminder: Reminder) {
        guard !reminder.isCompleted else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        if let notes = reminder.notes, !notes.isEmpty {
            content.body = notes
        } else {
            content.body = "Reminder due"
        }
        content.sound = .default
        content.userInfo = ["reminderID": reminder.id.uuidString]

        let calendar = Calendar.current
        let comps: DateComponents
        let repeats: Bool

        switch reminder.repeatFrequency {
        case .none:
            comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.dueDate)
            repeats = false
        case .daily:
            comps = calendar.dateComponents([.hour, .minute], from: reminder.dueDate)
            repeats = true
        case .weekly:
            comps = calendar.dateComponents([.weekday, .hour, .minute], from: reminder.dueDate)
            repeats = true
        case .monthly:
            // Note: reminders scheduled for days 29-31 will be skipped in shorter months.
            comps = calendar.dateComponents([.day, .hour, .minute], from: reminder.dueDate)
            repeats = true
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
        let request = UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: trigger)
        center.add(request)
    }

    func cancel(for reminder: Reminder) {
        center.removePendingNotificationRequests(withIdentifiers: [reminder.id.uuidString])
    }

    func reschedule(for reminder: Reminder) {
        cancel(for: reminder)
        schedule(for: reminder)
    }
}
