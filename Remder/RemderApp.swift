import SwiftUI
import SwiftData
import UserNotifications

@main
struct RemderApp: App {
    /// Shared so notification actions (handled outside any view) can read and write reminders.
    static let sharedContainer: ModelContainer = {
        do {
            if UITestMode.isActive {
                return try ModelContainer(
                    for: SharedStore.schema,
                    configurations: ModelConfiguration(schema: SharedStore.schema, isStoredInMemoryOnly: true)
                )
            }
            return try SharedStore.makeContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationManager.shared.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            AppGate()
        }
        .modelContainer(Self.sharedContainer)
    }
}
