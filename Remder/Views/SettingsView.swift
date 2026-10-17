import AVFoundation
import AppIntents
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var reminders: [Reminder]

    @AppStorage(AppSettings.Key.sound) private var sound: ReminderSound = .standard
    @AppStorage(AppSettings.Key.snoozeMinutes) private var snoozeMinutes = 10
    @AppStorage(AppSettings.Key.defaultPriority) private var defaultPriority: Priority = .medium
    @AppStorage(AppSettings.Key.defaultLeadMinutes) private var defaultLeadMinutes = 0
    @AppStorage(AppSettings.Key.defaultAlarm) private var defaultAlarm = false
    @AppStorage(AppSettings.Key.defaultNagMinutes) private var defaultNagMinutes = 0
    @AppStorage(AppSettings.Key.useAppleIntelligence) private var useAppleIntelligence = true
    @AppStorage(AppSettings.Key.morningBriefEnabled) private var morningBriefEnabled = true
    @AppStorage(AppSettings.Key.morningBriefMinutes) private var morningBriefMinutes = 8 * 60
    @AppStorage(AppSettings.Key.eveningCheckInEnabled) private var eveningCheckInEnabled = false
    @AppStorage(AppSettings.Key.eveningCheckInMinutes) private var eveningCheckInMinutes = 20 * 60
    @State private var editingPlace: AppSettings.Place?
    /// Bumped after saving a place, so the rows re-read `AppSettings`.
    @State private var placesVersion = 0

    @State private var appLock = AppLock.shared
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmingClear = false
    @State private var auth = AuthManager.shared
    @State private var sync = SyncEngine.shared
    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false
    @State private var isSigningOut = false
    @State private var accountError: String?
    /// Keeps "Syncing…" up briefly after a tap, so a quick sync doesn't just flicker.
    @State private var isManualSyncing = false
    @State private var syncFinished = 0

    private var completedCount: Int { reminders.filter(\.isCompleted).count }

    var body: some View {
        NavigationStack {
            Form {
                accountSection

                Section {
                    NavigationLink {
                        SoundPickerView(selection: $sound)
                    } label: {
                        LabeledContent("Sound", value: sound.label)
                    }

                    Picker("Snooze for", selection: $snoozeMinutes) {
                        ForEach(AppSettings.snoozeOptions, id: \.self) { minutes in
                            Text(minutes == 60 ? "1 hour" : "\(minutes) min").tag(minutes)
                        }
                    }

                    LabeledContent("Notifications") {
                        if notificationStatus == .denied {
                            Button("Turn On in Settings", action: openSystemSettings)
                        } else {
                            Text(notificationStatus == .notDetermined ? "Not set" : "On")
                        }
                    }
                } header: {
                    Text("Notifications")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { appLock.isEnabled },
                        set: { newValue in Task { await appLock.setEnabled(newValue) } }
                    )) {
                        Label("Lock with \(appLock.methodName)", systemImage: appLock.methodIcon)
                    }
                    .disabled(!appLock.isAvailable)

                    if appLock.isEnabled {
                        Picker("Require", selection: $appLock.delay) {
                            ForEach(AppLock.Delay.allCases) { Text($0.label).tag($0) }
                        }
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    if appLock.isAvailable {
                        Text("Reminders, notifications and the Dynamic Island keep working while Remder is locked. Only opening the app needs \(appLock.methodName).")
                    } else {
                        Text("Set up a passcode in the Settings app to lock Remder.")
                    }
                }

                Section {
                    Picker("Priority", selection: $defaultPriority) {
                        ForEach(Priority.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Alarm", isOn: Binding(
                        get: { defaultAlarm },
                        set: { newValue in
                            defaultAlarm = newValue
                            if newValue {
                                Task { if !(await AlarmScheduler.shared.requestAuthorization()) { defaultAlarm = false } }
                            }
                        }
                    ))
                    Picker("Keep reminding", selection: $defaultNagMinutes) {
                        ForEach(AppSettings.nagOptions, id: \.self) { Text(AppSettings.nagLabel($0)).tag($0) }
                    }
                    Picker("Dynamic Island countdown", selection: $defaultLeadMinutes) {
                        ForEach(ReminderFormView.leadTimeOptions, id: \.self) { minutes in
                            Text(ReminderFormView.leadTimeLabel(minutes)).tag(minutes)
                        }
                    }
                } header: {
                    Text("New Reminders")
                } footer: {
                    Text("Starting values for reminders you create. You can still change them on each reminder.")
                }

                Section {
                    Toggle(isOn: $morningBriefEnabled.animation()) {
                        SettingsIconLabel("Morning Summary", systemImage: "sun.max.fill", color: .orange)
                    }
                    if morningBriefEnabled {
                        DatePicker("Time", selection: timeBinding($morningBriefMinutes), displayedComponents: .hourAndMinute)
                    }
                    Toggle(isOn: $eveningCheckInEnabled.animation()) {
                        SettingsIconLabel("Evening Check-in", systemImage: "moon.stars.fill", color: .indigo)
                    }
                    if eveningCheckInEnabled {
                        DatePicker("Time", selection: timeBinding($eveningCheckInMinutes), displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Daily Brief")
                } footer: {
                    Text("A morning notification with what's due today, and an evening one if anything's still open.")
                }
                .onChange(of: [morningBriefEnabled, eveningCheckInEnabled]) { BriefScheduler.shared.refreshSoon() }
                .onChange(of: [morningBriefMinutes, eveningCheckInMinutes]) { BriefScheduler.shared.refreshSoon() }

                Section {
                    ForEach(AppSettings.Place.allCases) { place in
                        let saved = placesVersion >= 0 ? AppSettings.place(place) : nil
                        Button {
                            editingPlace = place
                        } label: {
                            LabeledContent {
                                Text(saved == nil ? "Not set" : "Set")
                                    .foregroundStyle(saved == nil ? .tertiary : .secondary)
                            } label: {
                                SettingsIconLabel(place.rawValue, systemImage: place.systemImage, color: place == .home ? .blue : .brown)
                            }
                        }
                        .tint(.primary)
                        .swipeActions {
                            if saved != nil {
                                Button("Clear", role: .destructive) {
                                    AppSettings.setPlace(place, to: nil)
                                    placesVersion += 1
                                }
                            }
                        }
                    }
                } header: {
                    Text("Places")
                } footer: {
                    Text("Used for location reminders, and in quick add: “Take out trash when I get home”.")
                }

                Section {
                    Toggle(isOn: $useAppleIntelligence) {
                        SettingsIconLabel("Smarter Quick Add", systemImage: "sparkles", tint: SettingsIconLabel.intelligence)
                    }
                    .disabled(!AIQuickAdd.isAvailable)

                    NavigationLink {
                        SiriShortcutsView()
                    } label: {
                        SettingsIconLabel("Siri & Shortcuts", systemImage: "waveform", tint: SettingsIconLabel.siri)
                    }
                } header: {
                    Text("Apple Intelligence & Siri")
                } footer: {
                    if let reason = AIQuickAdd.unavailableReason {
                        Text("\(reason) Quick add still understands dates, #categories and !priority.")
                    } else {
                        Text("Quick add uses Apple Intelligence to understand phrasing like “after work on Friday”.")
                    }
                }

                Section {
                    Button("Delete Completed Reminders", role: .destructive) { confirmingClear = true }
                        .disabled(completedCount == 0)
                } header: {
                    Text("Completed Reminders")
                }

                Section {
                    Button {
                        confirmingSignOut = true
                    } label: {
                        HStack {
                            Text("Sign Out")
                            Spacer()
                            if isSigningOut { ProgressView() }
                        }
                    }
                    .disabled(isSigningOut)
                    .confirmationDialog("Sign out of Remder?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive, action: signOut)
                    } message: {
                        Text("Your reminders stay in your account and come back when you sign in again. They'll be removed from this iPhone.")
                    }
                    Button("Delete Account", role: .destructive) { confirmingDelete = true }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Signed in with \(auth.signInMethod).")
                }
            }
            .sectionNavigationBar(title: "Settings")
            .confirmationDialog(
                "Delete \(completedCount) completed reminder\(completedCount == 1 ? "" : "s")?",
                isPresented: $confirmingClear,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: deleteCompleted)
            }
            .alert("Delete your account?", isPresented: $confirmingDelete) {
                Button("Delete Account", role: .destructive, action: deleteAccount)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account and every reminder, note and category in it, on all your devices. This can't be undone.")
            }
            .alert("Something Went Wrong", isPresented: Binding(get: { accountError != nil }, set: { if !$0 { accountError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(accountError ?? "")
            }
            .sheet(item: $editingPlace) { place in
                LocationPickerView(title: place.rawValue, current: AppSettings.place(place), choosesTrigger: false) { picked in
                    var picked = picked
                    picked.name = place.rawValue
                    AppSettings.setPlace(place, to: picked)
                    placesVersion += 1
                }
            }
            .task(id: scenePhase) {
                notificationStatus = await NotificationManager.shared.authorizationStatus()
            }
            .onChange(of: sound) {
                // Pending notifications keep the sound they were scheduled with; rebuild them.
                Task { await NotificationManager.shared.resync(reminders: reminders) }
            }
            .onChange(of: snoozeMinutes) {
                NotificationManager.shared.registerCategories()
            }
        }
    }

    private var accountSection: some View {
        Section {
            HStack(spacing: 14) {
                Text(auth.initials)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(
                        LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.displayName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(auth.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 6)

            Button(action: syncNow) {
                HStack {
                    Label {
                        Text("Sync")
                    } icon: {
                        Image(systemName: syncIcon)
                            .foregroundStyle(syncTint)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: syncFinished)
                    }
                    .foregroundStyle(.primary)
                    Spacer()
                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    }
                    Text(syncDescription)
                        .font(.subheadline)
                        .foregroundStyle(syncFailed ? .red : .secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                .animation(.smooth(duration: 0.3), value: isSyncing)
            }
            .tint(.primary)
            .disabled(isSyncing)
        } footer: {
            if case .failed(let message) = sync.status {
                Text("\(message) Your changes are saved on this iPhone and will sync later.")
            }
        }
    }

    /// Minutes after midnight shown as a time of day.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(byAdding: .minute, value: minutes.wrappedValue, to: Calendar.current.startOfDay(for: .now)) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var isSyncing: Bool { isManualSyncing || sync.status == .syncing }

    private func syncNow() {
        isManualSyncing = true
        Task {
            let start = ContinuousClock.now
            await sync.syncNow()
            try? await Task.sleep(until: start + .milliseconds(700))
            isManualSyncing = false
            if !syncFailed { syncFinished += 1 }
        }
    }

    private var syncFailed: Bool {
        if case .failed = sync.status { return true }
        return false
    }

    private var syncIcon: String {
        if isSyncing { return "icloud" }
        switch sync.status {
        case .syncing: return "icloud"
        case .failed: return "exclamationmark.icloud.fill"
        case .idle: return "checkmark.icloud.fill"
        }
    }

    private var syncTint: Color {
        if isSyncing { return .secondary }
        switch sync.status {
        case .syncing: return .secondary
        case .failed: return .orange
        case .idle: return .green
        }
    }

    private var syncDescription: String {
        if isSyncing { return "Syncing…" }
        switch sync.status {
        case .syncing: return "Syncing…"
        case .failed: return "Couldn't sync. Tap to retry"
        case .idle:
            guard let date = sync.lastSyncedAt else { return "Not synced yet" }
            if Date.now.timeIntervalSince(date) < 60 { return "Up to date" }
            return "Synced \(date.formatted(.relative(presentation: .named)))"
        }
    }

    private func signOut() {
        isSigningOut = true
        Task {
            await auth.signOut()
            isSigningOut = false
        }
    }

    private func deleteAccount() {
        Task {
            do {
                try await auth.deleteAccount()
            } catch {
                accountError = AccountError.message(for: error)
            }
        }
    }

    private func deleteCompleted() {
        for reminder in reminders where reminder.isCompleted {
            NotificationManager.shared.cancel(for: reminder)
            modelContext.delete(reminder)
        }
        try? modelContext.save()
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// A Settings-app style row label: a white symbol on a small colored rounded square.
private struct SettingsIconLabel: View {
    static let intelligence = AnyShapeStyle(LinearGradient(
        colors: [.orange, .pink, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing
    ))
    static let siri = AnyShapeStyle(LinearGradient(
        colors: [.indigo, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing
    ))

    let title: String
    let systemImage: String
    let tint: AnyShapeStyle

    init(_ title: String, systemImage: String, tint: AnyShapeStyle) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    init(_ title: String, systemImage: String, color: Color) {
        self.init(title, systemImage: systemImage, tint: AnyShapeStyle(color))
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

/// What to say to Siri, with a way into the Shortcuts app.
private struct SiriShortcutsView: View {
    @Environment(AppNavigation.self) private var navigation

    private struct Phrase: Identifiable {
        let phrase: String
        let detail: String
        let systemImage: String
        let color: Color
        var id: String { phrase }
    }

    private let phrases = [
        Phrase(phrase: "Add a reminder in Remder", detail: "Then say it naturally, like “call mom tomorrow at 5”. Or “Add a Work reminder in Remder” to pick the list.",
               systemImage: "plus", color: .blue),
        Phrase(phrase: "What's next in Remder", detail: "Hear your next few reminders.",
               systemImage: "list.bullet", color: .orange),
        Phrase(phrase: "Complete a Remder reminder", detail: "Pick a reminder and mark it done.",
               systemImage: "checkmark", color: .green),
    ]

    var body: some View {
        List {
            Section {
                SiriTipView(intent: AddReminderIntent())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 29, height: 29)
                        .background(SettingsIconLabel.intelligence, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("“Remind me in Remder to call mom tomorrow at 5”")
                            .font(.body.weight(.medium))
                        Text("Say it all at once. Siri fills in the title, time, list and repeat for you.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("With Apple Intelligence")
            } footer: {
                Text("On iPhones with Apple Intelligence, like iPhone 15 Pro and later.")
            }

            Section {
                ForEach(phrases) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 29, height: 29)
                            .background(item.color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("“\(item.phrase)”")
                                .font(.body.weight(.medium))
                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Ask Siri")
            } footer: {
                Text("These work on every iPhone. Siri asks what to remind you about, and when, if you didn't say a time.")
            }

            Section {
                Button {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                } label: {
                    HStack {
                        SettingsIconLabel("Open Shortcuts", systemImage: "square.2.layers.3d.fill", color: .pink)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            } footer: {
                Text("Find Remder's actions in the Shortcuts app to build automations, like adding a reminder when you leave work.")
            }
        }
        .navigationTitle("Siri & Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { navigation.isShowingDetail = true }
        .onDisappear { navigation.isShowingDetail = false }
    }
}

private struct SoundPickerView: View {
    @Environment(AppNavigation.self) private var navigation
    @Binding var selection: ReminderSound
    @State private var player: AVAudioPlayer?

    var body: some View {
        List {
            Section {
                ForEach(ReminderSound.allCases) { sound in
                    Button {
                        selection = sound
                        preview(sound)
                    } label: {
                        HStack {
                            Text(sound.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if sound == selection {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .tint(.primary)
                }
            } footer: {
                Text("Tap a sound to hear it. \"Default\" uses your iPhone's notification sound. Sounds play at your ringer volume and are muted when the phone is on silent.")
            }
        }
        .navigationTitle("Sound")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { navigation.isShowingDetail = true }
        .onDisappear { navigation.isShowingDetail = false }
    }

    private func preview(_ sound: ReminderSound) {
        player?.stop()
        guard let name = sound.fileName,
              let url = Bundle.main.url(forResource: name, withExtension: nil) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
