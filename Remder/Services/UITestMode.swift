import Foundation

/// Launch arguments used by the UI tests (RemderUITests).
///
/// `-uiTesting` starts the app signed in as a local test user, with an empty in-memory
/// database, no splash, no permission prompts and no cloud sync, so tests are fast, repeatable
/// and never touch real data. Add `-signedOut` to start on the welcome screen instead.
enum UITestMode {
    static let isActive = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    static let startsSignedOut = ProcessInfo.processInfo.arguments.contains("-signedOut")
}
