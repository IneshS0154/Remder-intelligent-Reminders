import SwiftUI

/// Sign-in screen: the brand up top, three ways in at the bottom. Always dark, like the icon.
struct WelcomeView: View {
    let brand: Namespace.ID

    @State private var auth = AuthManager.shared
    @State private var path: [Route] = []
    @State private var busyProvider: AuthManager.Provider?
    @State private var errorMessage: String?
    @State private var appeared = false

    enum Route: Hashable {
        case email
        case checkEmail(String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                WelcomeBackground()

                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    BrandMark(size: 72)
                        .matchedGeometryEffect(id: "mark", in: brand)

                    Text("Remder")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 14)

                    Text("Reminders that actually remind you.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 6)

                    Spacer(minLength: 32)

                    features
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)

                    Spacer(minLength: 32)

                    buttons
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)

                    Text("Your reminders are saved to your account and synced to your devices.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .padding(.horizontal, 24)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .email:
                    EmailAuthView { email in path.append(.checkEmail(email)) }
                case .checkEmail(let email):
                    CheckEmailView(email: email) { path.removeLast() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("Couldn't Sign In", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.6).delay(0.15)) { appeared = true }
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 18) {
            FeatureRow(icon: "bell.badge.fill", tint: .orange, title: "Never miss a thing",
                       detail: "Notifications, alarms and a live countdown.")
            FeatureRow(icon: "sparkles", tint: .purple, title: "Just type it",
                       detail: "“Gym every Monday 7am” is all it takes.")
            FeatureRow(icon: "icloud.fill", tint: .blue, title: "Safe in your account",
                       detail: "Sign in on a new iPhone and it's all there.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            AuthButton(style: .light, isBusy: busyProvider == .apple) {
                Image(systemName: "apple.logo").font(.system(size: 19, weight: .medium))
                Text("Continue with Apple")
            } action: {
                signIn(with: .apple)
            }

            AuthButton(style: .dark, isBusy: busyProvider == .google) {
                GoogleLogo().frame(width: 18, height: 18)
                Text("Continue with Google")
            } action: {
                signIn(with: .google)
            }

            AuthButton(style: .outline, isBusy: false) {
                Image(systemName: "envelope.fill").font(.system(size: 16, weight: .medium))
                Text("Continue with Email")
            } action: {
                path.append(.email)
            }
        }
        .disabled(busyProvider != nil)
    }

    private func signIn(with provider: AuthManager.Provider) {
        busyProvider = provider
        Task {
            defer { busyProvider = nil }
            do {
                try await auth.signIn(with: provider)
            } catch {
                let message = AccountError.message(for: error)
                if !message.isEmpty { errorMessage = message }
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

/// Full-width capsule button used on the sign-in screens.
struct AuthButton<Label: View>: View {
    enum Style { case light, dark, outline }

    let style: Style
    let isBusy: Bool
    @ViewBuilder let label: Label
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 10) { label }
                    .opacity(isBusy ? 0 : 1)
                if isBusy {
                    ProgressView().tint(style == .light ? .black : .white)
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(style == .light ? Color.black : Color.white)
            .background {
                switch style {
                case .light: Capsule().fill(.white)
                case .dark: Capsule().fill(Color(white: 0.14))
                case .outline: Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// Black with a slow, faint glow behind the bell.
struct WelcomeBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [Color.indigo.opacity(0.35), Color.purple.opacity(0.12), .clear],
                center: UnitPoint(x: drift ? 0.62 : 0.38, y: 0.18),
                startRadius: 10, endRadius: 360
            )
            .blur(radius: 30)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

/// Google's four-color "G".
struct GoogleLogo: View {
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let line = side * 0.2
            let radius = (side - line) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func arc(_ from: Double, _ to: Double, _ color: Color) {
                var path = Path()
                path.addArc(center: center, radius: radius, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: line, lineCap: .butt))
            }
            arc(-138, -40, Color(red: 0.918, green: 0.263, blue: 0.208))  // red
            arc(142, 222, Color(red: 0.984, green: 0.737, blue: 0.020))   // yellow
            arc(36, 142, Color(red: 0.204, green: 0.659, blue: 0.325))    // green
            arc(0, 36, Color(red: 0.259, green: 0.522, blue: 0.957))      // blue
            let bar = CGRect(x: center.x - line * 0.1, y: center.y - line / 2, width: radius + line / 2 + line * 0.1, height: line)
            context.fill(Path(bar), with: .color(Color(red: 0.259, green: 0.522, blue: 0.957)))
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    @Previewable @Namespace var brand
    WelcomeView(brand: brand)
}
