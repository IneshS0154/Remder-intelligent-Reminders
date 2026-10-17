import Foundation
import Observation
import Supabase

/// The Supabase project behind Remder accounts and sync.
/// The publishable key is meant to ship in apps; row-level security protects the data.
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://zjxmzcbdckvqkuqqlkyl.supabase.co")!,
    supabaseKey: "sb_publishable_7wW09-qVEtjssRs0gWcEjg_B54FV2w_",
    options: SupabaseClientOptions(
        auth: .init(redirectToURL: AuthManager.redirectURL, emitLocalSessionAsInitialSession: true)
    )
)

/// Signing in and out. Remder needs an account, so the app shows the welcome screen until
/// there's a session. A stored session counts even if it's expired: the app works offline
/// and the token refreshes once there's a connection.
@MainActor
@Observable
final class AuthManager {
    static let shared = AuthManager()

    /// Where email confirmation, password reset and OAuth links return to.
    nonisolated static let redirectURL = URL(string: "remder://auth-callback")!

    enum State: Equatable {
        case loading
        case signedOut
        case signedIn
    }

    enum Provider: String {
        case apple, google

        var name: String { self == .apple ? "Apple" : "Google" }
        var supabaseProvider: Supabase.Provider { self == .apple ? .apple : .google }
    }

    private(set) var state: State = .loading
    private(set) var user: User?
    /// Set when a password-reset link opens the app; shows the "new password" screen.
    var isRecoveringPassword = false
    /// Sign-in methods switched on in the Supabase dashboard (nil until checked).
    private(set) var enabledProviders: Set<String>?

    private var listener: Task<Void, Never>?

    private init() {}

    func start() {
        if UITestMode.isActive {
            state = UITestMode.startsSignedOut ? .signedOut : .signedIn
            enabledProviders = []
            return
        }
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                self?.handle(event, session: session)
            }
        }
        Task { await loadEnabledProviders() }
    }

    private func handle(_ event: AuthChangeEvent, session: Session?) {
        switch event {
        case .signedOut, .userDeleted:
            user = nil
            state = .signedOut
            SyncEngine.shared.stop()
        case .passwordRecovery:
            isRecoveringPassword = true
            fallthrough
        default:
            guard let session else {
                if event == .initialSession { state = .signedOut }
                return
            }
            let isNewUser = user?.id != session.user.id
            user = session.user
            state = .signedIn
            if isNewUser { SyncEngine.shared.start(userID: session.user.id) }
        }
    }

    // MARK: - Profile

    var displayName: String {
        if UITestMode.isActive { return "Test User" }
        let metadata = user?.userMetadata ?? [:]
        for key in ["full_name", "name"] {
            if case let .string(name)? = metadata[key], !name.trimmingCharacters(in: .whitespaces).isEmpty {
                return name
            }
        }
        return user?.email?.components(separatedBy: "@").first?.capitalized ?? "Remder User"
    }

    var email: String { UITestMode.isActive ? "test@remder.app" : user?.email ?? "" }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        return parts.compactMap(\.first).map(String.init).joined().uppercased()
    }

    /// "Apple", "Google" or "Email".
    var signInMethod: String {
        switch user?.appMetadata["provider"] {
        case .string("apple")?: return "Apple"
        case .string("google")?: return "Google"
        default: return "Email"
        }
    }

    // MARK: - Email

    /// Returns true when the account needs its email confirmed before signing in.
    func signUp(name: String, email: String, password: String) async throws -> Bool {
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["full_name": .string(name)],
            redirectTo: Self.redirectURL
        )
        if case .session = response { return false }
        return true
    }

    func signIn(email: String, password: String) async throws {
        if UITestMode.isActive {
            // Any password but "wrong" works, so tests can cover both outcomes offline.
            guard password != "wrong" else { throw AccountError.testInvalidCredentials }
            state = .signedIn
            return
        }
        try await supabase.auth.signIn(email: email, password: password)
    }

    func resendConfirmation(email: String) async throws {
        try await supabase.auth.resend(email: email, type: .signup, emailRedirectTo: Self.redirectURL)
    }

    func sendPasswordReset(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email, redirectTo: Self.redirectURL)
    }

    func updatePassword(_ password: String) async throws {
        try await supabase.auth.update(user: UserAttributes(password: password))
    }

    // MARK: - Apple and Google

    func isEnabled(_ provider: Provider) -> Bool {
        enabledProviders?.contains(provider.rawValue) ?? true
    }

    /// Signs in through the provider's web page in a secure browser sheet.
    func signIn(with provider: Provider) async throws {
        if enabledProviders == nil { await loadEnabledProviders() }
        guard isEnabled(provider) else { throw AccountError.providerNotSetUp(provider.name) }
        try await supabase.auth.signInWithOAuth(provider: provider.supabaseProvider, redirectTo: Self.redirectURL)
    }

    /// Asks the project which sign-in methods are on, so a disabled one gets a clear message
    /// instead of an error page in the browser.
    func loadEnabledProviders() async {
        var request = URLRequest(url: URL(string: "https://zjxmzcbdckvqkuqqlkyl.supabase.co/auth/v1/settings")!)
        request.setValue("sb_publishable_7wW09-qVEtjssRs0gWcEjg_B54FV2w_", forHTTPHeaderField: "apikey")
        struct Settings: Decodable { let external: [String: Bool] }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return }
        enabledProviders = Set(settings.external.filter(\.value).map(\.key))
    }

    // MARK: - Links, sign-out, deletion

    /// Email confirmation, password reset and OAuth links.
    func handle(_ url: URL) {
        guard url.scheme == Self.redirectURL.scheme else { return }
        supabase.auth.handle(url)
    }

    /// Sends any unsynced changes, signs out, and clears this iPhone's copy of the data.
    func signOut() async {
        if UITestMode.isActive {
            await SyncEngine.shared.clearLocalData()
            state = .signedOut
            return
        }
        await SyncEngine.shared.syncNow()
        do {
            try await supabase.auth.signOut()
        } catch {
            try? await supabase.auth.signOut(scope: .local)
        }
        await SyncEngine.shared.clearLocalData()
    }

    /// Deletes the account and everything synced to it.
    func deleteAccount() async throws {
        try await supabase.rpc("delete_account").execute()
        try? await supabase.auth.signOut(scope: .local)
        await SyncEngine.shared.clearLocalData()
    }
}

enum AccountError: LocalizedError {
    case providerNotSetUp(String)
    case signedOut
    case testInvalidCredentials

    /// Siri and Shortcuts can run while nobody is signed in; reminders need an account.
    static func requireSignIn() throws {
        guard UITestMode.isActive || supabase.auth.currentSession != nil else { throw AccountError.signedOut }
    }

    var errorDescription: String? {
        switch self {
        case .signedOut:
            return "Open Remder and sign in first."
        case .testInvalidCredentials:
            return "That email and password don't match."
        case .providerNotSetUp(let name):
            return "Sign in with \(name) isn't available yet. Use email for now."
        }
    }

    /// Turns Supabase errors into short messages for alerts.
    static func message(for error: Error) -> String {
        if let error = error as? AccountError { return error.errorDescription ?? "" }
        if (error as NSError).domain == "com.apple.AuthenticationServices.WebAuthenticationSession" {
            return ""  // The person closed the sign-in sheet.
        }
        if let error = error as? AuthError {
            switch error.errorCode {
            case .invalidCredentials: return "That email and password don't match."
            case .emailNotConfirmed: return "Confirm your email first. Check your inbox for the link."
            case .userAlreadyExists, .emailExists: return "An account with this email already exists. Sign in instead."
            case .weakPassword: return "Choose a stronger password, at least 8 characters."
            case .overEmailSendRateLimit, .overRequestRateLimit: return "Too many attempts. Wait a minute and try again."
            default: return error.message
            }
        }
        if (error as? URLError) != nil { return "You're offline. Check your connection and try again." }
        return error.localizedDescription
    }
}
