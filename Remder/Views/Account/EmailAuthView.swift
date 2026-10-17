import SwiftUI

/// Sign in or create an account with email and password.
struct EmailAuthView: View {
    /// Called with the address when a new account needs its email confirmed.
    let onNeedsConfirmation: (String) -> Void

    @State private var auth = AuthManager.shared
    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var resetSentTo: String?
    @FocusState private var focus: Field?

    enum Mode: String, CaseIterable {
        case signIn = "Sign In"
        case signUp = "Create Account"
    }

    private enum Field { case name, email, password }

    private var emailIsValid: Bool {
        email.trimmingCharacters(in: .whitespaces).range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    private var canSubmit: Bool {
        guard emailIsValid, !isWorking else { return false }
        switch mode {
        case .signIn: return !password.isEmpty
        case .signUp: return password.count >= 8 && !name.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        ZStack {
            WelcomeBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(mode == .signIn ? "Welcome back" : "Create your account")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                    Text(mode == .signIn ? "Sign in to get your reminders." : "It takes less than a minute.")
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 6)
                        .contentTransition(.opacity)

                    Picker("Mode", selection: $mode.animation(.snappy)) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 28)

                    VStack(spacing: 12) {
                        if mode == .signUp {
                            AuthField(icon: "person.fill", placeholder: "Your name", text: $name)
                                .textContentType(.name)
                                .textInputAutocapitalization(.words)
                                .focused($focus, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focus = .email }
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        AuthField(icon: "envelope.fill", placeholder: "Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }

                        AuthField(icon: "lock.fill", placeholder: "Password", text: $password, isSecure: !showPassword) {
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundStyle(.white.opacity(0.5))
                                    .frame(width: 32, height: 32)
                            }
                            .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                        }
                        // iOS offers a strong password for new accounts; its panel would block UI tests.
                        .textContentType(mode == .signIn || UITestMode.isActive ? .password : .newPassword)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                    }
                    .padding(.top, 20)

                    HStack {
                        if mode == .signUp {
                            Label("At least 8 characters", systemImage: password.count >= 8 ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(password.count >= 8 ? .green : .white.opacity(0.45))
                                .contentTransition(.symbolEffect(.replace))
                        } else {
                            Spacer()
                            Button("Forgot password?", action: sendReset)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .font(.footnote.weight(.medium))
                    .padding(.top, 12)
                    .padding(.horizontal, 4)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.42))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.top, 16)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    AuthButton(style: .light, isBusy: isWorking) {
                        Text(mode.rawValue)
                    } action: {
                        submit()
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit || isWorking ? 1 : 0.45)
                    .accessibilityIdentifier("auth.submit")
                    .padding(.top, 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy, value: errorMessage)
        .onChange(of: mode) { errorMessage = nil }
        .onAppear { focus = .email }
        .alert("Check Your Email", isPresented: Binding(get: { resetSentTo != nil }, set: { if !$0 { resetSentTo = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("If an account exists for \(resetSentTo ?? ""), we've sent a link to reset its password.")
        }
    }

    private func submit() {
        guard canSubmit else { return }
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                switch mode {
                case .signIn:
                    try await auth.signIn(email: email, password: password)
                case .signUp:
                    let needsConfirmation = try await auth.signUp(
                        name: name.trimmingCharacters(in: .whitespaces), email: email, password: password
                    )
                    if needsConfirmation { onNeedsConfirmation(email) }
                }
            } catch {
                errorMessage = AccountError.message(for: error)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func sendReset() {
        guard emailIsValid else {
            errorMessage = "Enter your email above, then tap “Forgot password?” again."
            focus = .email
            return
        }
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        Task {
            do {
                try await auth.sendPasswordReset(email: email)
                resetSentTo = email
            } catch {
                errorMessage = AccountError.message(for: error)
            }
        }
    }
}

/// A rounded dark text field with a leading icon.
struct AuthField<Trailing: View>: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 20)
            Group {
                if isSecure {
                    SecureField("", text: $text, prompt: prompt)
                } else {
                    TextField("", text: $text, prompt: prompt)
                }
            }
            .foregroundStyle(.white)
            trailing
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(.white.opacity(0.35))
    }
}

extension AuthField where Trailing == EmptyView {
    init(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool = false) {
        self.init(icon: icon, placeholder: placeholder, text: text, isSecure: isSecure) { EmptyView() }
    }
}

/// Shown after creating an account until the email link is tapped.
struct CheckEmailView: View {
    let email: String
    let onBack: () -> Void

    @State private var bounce = false
    @State private var cooldown = 0
    @State private var message: String?

    var body: some View {
        ZStack {
            WelcomeBackground()

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 64))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.red, .white)
                    .symbolEffect(.bounce, value: bounce)
                    .frame(width: 128, height: 128)
                    .background(Color(white: 0.12), in: Circle())

                Text("Check your inbox")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 28)

                Text("We sent a link to **\(email)**. Tap it on this iPhone to finish creating your account.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 10)

                if let message {
                    Text(message)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.top, 14)
                        .transition(.opacity)
                }

                Spacer()

                VStack(spacing: 12) {
                    AuthButton(style: .light, isBusy: false) {
                        Text("Open Mail")
                    } action: {
                        if let url = URL(string: "message://") { UIApplication.shared.open(url) }
                    }

                    AuthButton(style: .outline, isBusy: false) {
                        Text(cooldown > 0 ? "Resend in \(cooldown)s" : "Resend Email")
                            .monospacedDigit()
                    } action: {
                        resend()
                    }
                    .disabled(cooldown > 0)
                    .opacity(cooldown > 0 ? 0.5 : 1)

                    Button("Back to Sign In", action: onBack)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .navigationBarBackButtonHidden()
        .animation(.snappy, value: message)
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            bounce.toggle()
            await startCooldown()
        }
    }

    private func resend() {
        Task {
            do {
                try await AuthManager.shared.resendConfirmation(email: email)
                message = "Sent again. It can take a minute to arrive."
                bounce.toggle()
                await startCooldown()
            } catch {
                message = nil
                message = AccountError.message(for: error)
            }
        }
    }

    private func startCooldown() async {
        cooldown = 30
        while cooldown > 0 {
            try? await Task.sleep(for: .seconds(1))
            cooldown -= 1
        }
    }
}

/// Opened by a password-reset link.
struct ResetPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var done = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(done ? "Password updated" : "Choose a new password")
                    .font(.title2.bold())
                if done {
                    Label("You're all set. Use it next time you sign in.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    SecureField("New password (at least 8 characters)", text: $password)
                        .textContentType(.newPassword)
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
                Spacer()
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if done {
                        Button("Done") { dismiss() }
                    } else if isWorking {
                        ProgressView()
                    } else {
                        Button("Save", action: save).disabled(password.count < 8)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    if !done { Button("Cancel") { dismiss() } }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await AuthManager.shared.updatePassword(password)
                withAnimation { done = true }
            } catch {
                errorMessage = AccountError.message(for: error)
            }
        }
    }
}
