import AVFoundation
import SwiftData
import SwiftUI

struct AboutView: View {
    @Query private var reminders: [Reminder]
    @Query private var categories: [ReminderCategory]

    /// Easter egg: tapping the icon rings the bell a little harder each time; the 7th tap sets it off.
    @State private var iconTaps = 0
    @State private var wiggle = 0
    @State private var showBellShower = false
    @State private var showSecret = false
    @State private var player: AVAudioPlayer?

    private static let tapsForSecret = 7

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    stats
                    ForEach(Self.featureGroups) { group in
                        featureSection(group)
                    }
                    privacy
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .sectionNavigationBar(title: "About")
            .overlay {
                if showBellShower {
                    BellShower()
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
            }
            .overlay(alignment: .top) {
                if showSecret {
                    secretCard
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            Button(action: tapIcon) {
                BrandMark(size: 58)
                    .keyframeAnimator(initialValue: 0.0, trigger: wiggle) { content, angle in
                        content.rotationEffect(.degrees(angle), anchor: .top)
                    } keyframes: { _ in
                        // Swing harder the closer you get to the secret.
                        let swing = 8.0 + Double(iconTaps) * 3
                        KeyframeTrack {
                            SpringKeyframe(swing, duration: 0.08)
                            SpringKeyframe(-swing, duration: 0.12)
                            SpringKeyframe(swing * 0.6, duration: 0.12)
                            SpringKeyframe(-swing * 0.3, duration: 0.12)
                            SpringKeyframe(0, duration: 0.2)
                        }
                    }
                    .frame(width: 104, height: 104)
                    .background(.black, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remder app icon")

            VStack(spacing: 4) {
                Text("Remder")
                    .font(.largeTitle.bold())
                Text(version)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Reminders that actually remind you: on time, in your words, on every screen you look at.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(.top, 8)
    }

    private var stats: some View {
        HStack(spacing: 12) {
            statTile(value: reminders.filter { !$0.isCompleted }.count, label: "Active", icon: "bell", tint: .accentColor)
            statTile(value: reminders.filter(\.isCompleted).count, label: "Completed", icon: "checkmark.circle", tint: .green)
            statTile(value: categories.count, label: "Categories", icon: "circle.grid.2x2", tint: .purple)
        }
    }

    private func statTile(value: Int, label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.title2.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private struct Feature: Identifiable {
        let icon: String
        let tint: Color
        let title: String
        let detail: String
        var id: String { title }
    }

    private struct FeatureGroup: Identifiable {
        let title: String
        let features: [Feature]
        var id: String { title }
    }

    private static let featureGroups: [FeatureGroup] = [
        FeatureGroup(title: "Never Miss a Thing", features: [
            Feature(icon: "bell.badge.fill", tint: .red, title: "On-time notifications",
                    detail: "Complete or snooze right from the notification."),
            Feature(icon: "alarm.fill", tint: .orange, title: "Alarms",
                    detail: "A real alarm that rings through Silent mode and Focus."),
            Feature(icon: "timer", tint: .indigo, title: "Live countdown",
                    detail: "The Dynamic Island and Lock Screen count down to what's next."),
            Feature(icon: "arrow.clockwise.circle.fill", tint: .pink, title: "Keep reminding",
                    detail: "Nudges you again every few minutes until it's done."),
        ]),
        FeatureGroup(title: "Add in Seconds", features: [
            Feature(icon: "sparkles", tint: .purple, title: "Quick add",
                    detail: "Type it like you'd say it. With Apple Intelligence it gets “after work on Friday” too."),
            Feature(icon: "waveform", tint: .blue, title: "Siri & Shortcuts",
                    detail: "“Add a reminder in Remder”, or say it all at once with Apple Intelligence."),
            Feature(icon: "repeat", tint: .teal, title: "Repeating reminders",
                    detail: "Daily, weekly or monthly, and it moves on when you're done."),
        ]),
        FeatureGroup(title: "Stay Organized", features: [
            Feature(icon: "circle.grid.2x2.fill", tint: .purple, title: "Categories",
                    detail: "Color-coded groups, one tap to filter."),
            Feature(icon: "note.text", tint: .orange, title: "Notes",
                    detail: "Attach detailed notes that show up when the reminder does."),
            Feature(icon: "flame.fill", tint: .red, title: "Streaks & insights",
                    detail: "See your streaks and how often you finish on time."),
            Feature(icon: "square.grid.2x2.fill", tint: .green, title: "Widgets",
                    detail: "What's next on your Home Screen and Lock Screen. Tick things off right there."),
        ]),
        FeatureGroup(title: "Yours, Everywhere", features: [
            Feature(icon: "icloud.fill", tint: .blue, title: "Synced to your account",
                    detail: "Sign in with Apple, Google or email, and your reminders follow you."),
            Feature(icon: "faceid", tint: .green, title: "Face ID lock",
                    detail: "Keep reminders private without missing a single alert."),
            Feature(icon: "speaker.wave.2.fill", tint: .pink, title: "Custom sounds",
                    detail: "Pick the sound that gets your attention."),
        ]),
    ]

    private func featureSection(_ group: FeatureGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(group.features.enumerated()), id: \.element.id) { index, feature in
                    if index > 0 { Divider().padding(.leading, 60) }
                    featureRow(feature.icon, feature.tint, feature.title, feature.detail)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var privacy: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Private by design")
                    .font(.subheadline.weight(.semibold))
                Text("Your reminders sync only to your own account, and only you can read them. Apple Intelligence reads quick add text on your iPhone; it never leaves the device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func featureRow(_ icon: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Text("Made by Iness with")
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.bounce, value: showSecret)
            }
            .font(.subheadline.weight(.medium))

            Text("© \(Date.now.formatted(.dateTime.year())) Remder")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }

    private var secretCard: some View {
        HStack(spacing: 12) {
            Text("🔔")
                .font(.largeTitle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ding ding! You found the secret bell.")
                    .font(.subheadline.weight(.semibold))
                Text("Not everything needs a reminder. Some things you just remember. Thanks for using Remder!")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { withAnimation(.snappy) { showSecret = false } }
    }

    // MARK: - Easter egg

    private func tapIcon() {
        iconTaps += 1
        wiggle += 1
        UIImpactFeedbackGenerator(style: iconTaps >= Self.tapsForSecret - 2 ? .heavy : .light).impactOccurred()

        guard iconTaps >= Self.tapsForSecret else { return }
        iconTaps = 0
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        ringBell()
        withAnimation(.snappy) {
            showBellShower = true
            showSecret = true
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            showBellShower = false
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.snappy) { showSecret = false }
        }
    }

    private func ringBell() {
        guard let url = Bundle.main.url(forResource: "Bell", withExtension: "wav") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

/// A shower of colorful bells falling down the screen.
private struct BellShower: View {
    private struct Bell {
        let x: Double          // 0...1 across the screen
        let delay: Double      // seconds before it starts falling
        let speed: Double      // screen heights per second
        let size: Double
        let spin: Double       // degrees per second
        let sway: Double       // horizontal sway amplitude in points
        let color: Color
    }

    private let bells: [Bell] = (0..<46).map { _ in
        Bell(
            x: .random(in: 0...1),
            delay: .random(in: 0...1.2),
            speed: .random(in: 0.35...0.6),
            size: .random(in: 18...34),
            spin: .random(in: -140...140),
            sway: .random(in: 6...22),
            color: [.red, .orange, .yellow, .green, .mint, .blue, .indigo, .purple, .pink].randomElement()!
        )
    }
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                for bell in bells {
                    let t = elapsed - bell.delay
                    guard t > 0 else { continue }
                    let y = -40 + t * bell.speed * (size.height + 80)
                    guard y < size.height + 40 else { continue }
                    let x = bell.x * size.width + sin(t * 3) * bell.sway

                    var symbol = context.resolve(Image(systemName: "bell.fill"))
                    symbol.shading = .color(bell.color)
                    var local = context
                    local.translateBy(x: x, y: y)
                    local.rotate(by: .degrees(t * bell.spin))
                    local.draw(symbol, in: CGRect(x: -bell.size / 2, y: -bell.size / 2, width: bell.size, height: bell.size))
                }
            }
        }
    }
}
