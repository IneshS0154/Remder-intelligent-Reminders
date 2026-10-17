import SwiftUI

/// Shown instead of the app's content while the app lock is engaged.
struct LockView: View {
    @Environment(\.scenePhase) private var scenePhase
    let appLock: AppLock

    /// Prompt automatically once per lock; after a cancel, wait for the button.
    @State private var didAutoPrompt = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "bell.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(spacing: 6) {
                Text("Remder is Locked")
                    .font(.title2.bold())
                Text("Your reminders and notifications keep working while the app is locked.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)

            Spacer()

            Button {
                Task { await appLock.unlock() }
            } label: {
                Label("Unlock with \(appLock.methodName)", systemImage: appLock.methodIcon)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear(perform: autoPrompt)
        .onChange(of: scenePhase) { autoPrompt() }
    }

    private func autoPrompt() {
        guard scenePhase == .active, !didAutoPrompt else { return }
        didAutoPrompt = true
        Task { await appLock.unlock() }
    }
}

/// Covers the app in the app switcher and while inactive, so reminders aren't visible there.
struct PrivacyCover: View {
    var body: some View {
        Image(systemName: "bell.fill")
            .font(.system(size: 34))
            .foregroundStyle(.white)
            .frame(width: 76, height: 76)
            .background(.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
