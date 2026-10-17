import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// Optional Face ID / Touch ID / passcode lock for the app's UI.
///
/// Only the screens are locked: notifications, their Complete/Snooze buttons, and the
/// Dynamic Island countdown keep working, because none of them go through the UI.
@Observable
final class AppLock {
    static let shared = AppLock()

    enum Delay: Int, CaseIterable, Identifiable {
        case immediately = 0
        case oneMinute = 60
        case fiveMinutes = 300
        case fifteenMinutes = 900

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .immediately: return "Immediately"
            case .oneMinute: return "After 1 minute"
            case .fiveMinutes: return "After 5 minutes"
            case .fifteenMinutes: return "After 15 minutes"
            }
        }
    }

    private enum Key {
        static let enabled = "appLockEnabled"
        static let delay = "appLockDelay"
    }

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Key.enabled) }
    }

    var delay: Delay {
        didSet { UserDefaults.standard.set(delay.rawValue, forKey: Key.delay) }
    }

    /// True while the app's content is hidden behind the lock screen.
    private(set) var isLocked: Bool
    /// True while the system Face ID / passcode prompt is up (the app is briefly inactive then).
    private(set) var isAuthenticating = false

    private var backgroundedAt: Date?

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: Key.enabled)
        isEnabled = enabled
        delay = Delay(rawValue: UserDefaults.standard.integer(forKey: Key.delay)) ?? .immediately
        isLocked = enabled
    }

    // MARK: - Biometry

    /// "Face ID", "Touch ID", "Optic ID", or "Passcode" when no biometrics are set up.
    var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    var methodIcon: String {
        switch methodName {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default: return "lock"
        }
    }

    /// False when the device has no passcode, so there's nothing to lock with.
    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    // MARK: - Locking

    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .background:
            if backgroundedAt == nil { backgroundedAt = .now }
        case .active:
            if isEnabled, !isLocked, let backgroundedAt,
               Date.now.timeIntervalSince(backgroundedAt) >= TimeInterval(delay.rawValue) {
                isLocked = true
            }
            backgroundedAt = nil
        default:
            break
        }
    }

    /// Shows the system prompt; unlocks on success.
    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        if await authenticate(reason: "Unlock Remder to see your reminders.") {
            withAnimation(.smooth(duration: 0.3)) { isLocked = false }
        }
    }

    /// Turning the lock on or off asks for authentication first, so it can't be switched off by someone else.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        let reason = enabled ? "Turn on the app lock for Remder." : "Turn off the app lock for Remder."
        if await authenticate(reason: reason) {
            isEnabled = enabled
        }
    }

    private func authenticate(reason: String) async -> Bool {
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
