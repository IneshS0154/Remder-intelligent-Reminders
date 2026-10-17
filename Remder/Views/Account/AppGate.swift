import SwiftUI

/// The app's first screen: the splash, then the welcome screen when signed out, or the app.
struct AppGate: View {
    @State private var auth = AuthManager.shared
    @State private var splashFinished = UITestMode.isActive
    @Namespace private var brand

    private enum Phase { case splash, welcome, app }

    private var phase: Phase {
        guard splashFinished, auth.state != .loading else { return .splash }
        return auth.state == .signedIn ? .app : .welcome
    }

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                SplashView(brand: brand) { splashFinished = true }
                    .transition(.opacity)
            case .welcome:
                WelcomeView(brand: brand)
                    .transition(.opacity)
            case .app:
                RootView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .animation(.smooth(duration: 0.55), value: phase)
        .task { auth.start() }
        .onOpenURL { auth.handle($0) }
        .sheet(isPresented: $auth.isRecoveringPassword) {
            ResetPasswordView()
        }
    }
}

/// The white bell on black from the app icon, shared by the launch screen, splash and welcome.
struct BrandMark: View {
    /// 64pt matches the launch screen's image, so the splash starts exactly where it left off.
    var size: CGFloat = 64

    var body: some View {
        Image("LaunchLogo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
