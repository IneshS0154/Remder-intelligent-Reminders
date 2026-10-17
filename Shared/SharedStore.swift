import Foundation
import SwiftData

/// The SwiftData store, kept in the App Group container so the app and its widgets share it.
enum SharedStore {
    static let appGroupID = "group.com.ineshsandivpersonalteam.Remder"

    static let schema = Schema([Reminder.self, ReminderCategory.self, Note.self, Completion.self])

    static func makeContainer() throws -> ModelContainer {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil else {
            // No App Group entitlement (e.g. a build without it): fall back to the app's own container.
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        }
        migrateLegacyStoreIfNeeded()
        let configuration = ModelConfiguration(schema: schema, groupContainer: .identifier(appGroupID))
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Before widgets, the store lived in the app's own Application Support folder. Copy it into
    /// the shared container once, so existing reminders, notes and categories carry over.
    private static func migrateLegacyStoreIfNeeded() {
        let fileManager = FileManager.default
        guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID),
              let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }

        let sharedDirectory = groupURL.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let legacyStore = appSupport.appending(path: "default.store")
        let sharedStore = sharedDirectory.appending(path: "default.store")
        guard legacyStore.path != sharedStore.path,
              fileManager.fileExists(atPath: legacyStore.path),
              !fileManager.fileExists(atPath: sharedStore.path)
        else { return }

        try? fileManager.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let source = appSupport.appending(path: "default.store" + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try? fileManager.copyItem(at: source, to: sharedDirectory.appending(path: "default.store" + suffix))
        }
    }
}
