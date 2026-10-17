import SwiftData
import SwiftUI

/// The Reminders section: Active and Completed tabs in a Liquid Glass tab bar, sharing the
/// add / edit / "reminder due" sheets and the category filter from the sidebar.
struct RemindersView: View {
    enum ListTab: Hashable { case active, completed }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppNavigation.self) private var navigation
    @Query(sort: \Reminder.dueDate) private var reminders: [Reminder]

    @State private var tab: ListTab = .active
    @State private var showingAddSheet = false
    @State private var showingQuickAdd = false
    /// Values from quick add's "Edit Details", shown in the full form once quick add closes.
    @State private var pendingPrefill: ParsedReminder?
    @State private var formPrefill: ParsedReminder?
    @State private var editingReminder: Reminder?
    @State private var dueReminder: Reminder?
    @State private var notificationsDenied = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Active", systemImage: "bell", value: ListTab.active) {
                NavigationStack {
                    ReminderListScreen(kind: .active, isSelected: tab == .active, notificationsDenied: notificationsDenied,
                                       onAdd: { showingQuickAdd = true },
                                       onAddFull: { showingAddSheet = true },
                                       onEdit: { editingReminder = $0 })
                }
            }
            Tab("Completed", systemImage: "checkmark.circle", value: ListTab.completed) {
                NavigationStack {
                    ReminderListScreen(kind: .completed, isSelected: tab == .completed, notificationsDenied: false,
                                       onAdd: { showingQuickAdd = true },
                                       onAddFull: { showingAddSheet = true },
                                       onEdit: { editingReminder = $0 })
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $showingQuickAdd, onDismiss: {
            // Present the full form only after quick add has finished closing.
            if let prefill = pendingPrefill {
                pendingPrefill = nil
                formPrefill = prefill
            }
        }) {
            QuickAddSheet(defaultCategory: navigation.selectedCategory) { pendingPrefill = $0 }
        }
        .sheet(isPresented: $showingAddSheet) {
            ReminderFormView(reminder: nil, defaultCategory: navigation.selectedCategory)
        }
        .sheet(item: $formPrefill) { prefill in
            ReminderFormView(reminder: nil, defaultCategory: navigation.selectedCategory, prefill: prefill)
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderFormView(reminder: reminder)
        }
        .sheet(item: $dueReminder) { reminder in
            ReminderAlertView(reminder: reminder)
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                notificationsDenied = await NotificationManager.shared.authorizationStatus() == .denied
            }
        }
        .onAppear(perform: handlePendingDeepLink)
        .onChange(of: DeepLinkRouter.shared.pendingReminderID) {
            handlePendingDeepLink()
        }
    }

    private func handlePendingDeepLink() {
        guard let id = DeepLinkRouter.shared.pendingReminderID else { return }
        if let match = reminders.first(where: { $0.id == id }) {
            editingReminder = nil
            tab = .active
            dueReminder = match
        }
        DeepLinkRouter.shared.pendingReminderID = nil
    }
}

/// One tab's list: category filter chips, then the matching reminders.
private struct ReminderListScreen: View {
    enum Kind { case active, completed }

    let kind: Kind
    /// Whether this tab is the one showing; switching to it plays the entrance animation.
    let isSelected: Bool
    let notificationsDenied: Bool
    /// "+" opens quick add; long-press it for the full form.
    let onAdd: () -> Void
    let onAddFull: () -> Void
    let onEdit: (Reminder) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var navigation
    @Query(sort: \Reminder.dueDate) private var reminders: [Reminder]
    @Query(sort: [SortDescriptor(\ReminderCategory.sortOrder), SortDescriptor(\ReminderCategory.createdDate)])
    private var categories: [ReminderCategory]

    @State private var confirmingClear = false

    private var colorsByName: [String: Color] {
        Dictionary(categories.map { ($0.name, $0.color.color) }, uniquingKeysWith: { first, _ in first })
    }

    private var shown: [Reminder] {
        reminders.filter { reminder in
            (kind == .completed) == reminder.isCompleted
                && (navigation.selectedCategory == nil || reminder.category == navigation.selectedCategory)
        }
        .sorted { lhs, rhs in
            // Most recently completed first; upcoming reminders soonest first.
            kind == .completed
                ? (lhs.completedDate ?? lhs.dueDate) > (rhs.completedDate ?? rhs.dueDate)
                // Location reminders have no time, so they go last.
                : lhs.isLocationBased != rhs.isLocationBased ? !lhs.isLocationBased : lhs.dueDate < rhs.dueDate
        }
    }

    var body: some View {
        List {
            if notificationsDenied {
                Section { notificationsDeniedBanner }
            }

            if !categories.isEmpty {
                categoryChips
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if !shown.isEmpty {
                Section {
                    ForEach(shown) { reminder in
                        ReminderRowView(reminder: reminder, categoryColor: colorsByName[reminder.category]) {
                            toggleComplete(reminder)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onEdit(reminder) }
                        .swipeActions {
                            Button(role: .destructive) { delete(reminder) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
        .contentMargins(.top, 4, for: .scrollContent)
        // Fade only the content in; the background stays put so the top bar doesn't flicker.
        .scrollContentBackground(.hidden)
        .modifier(TabEntrance(isSelected: isSelected))
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .overlay {
            if shown.isEmpty { emptyState }
        }
        .sectionNavigationBar(title: navigation.selectedCategory ?? "Remder")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if kind == .active {
                    Menu {
                        Button("Quick Add", systemImage: "text.cursor", action: onAdd)
                        Button("New Reminder…", systemImage: "square.and.pencil", action: onAddFull)
                    } label: {
                        Image(systemName: "plus")
                    } primaryAction: {
                        onAdd()
                    }
                    .accessibilityLabel("New Reminder")
                } else {
                    Button("Clear") { confirmingClear = true }
                        .disabled(shown.isEmpty)
                }
            }
        }
        .confirmationDialog("Delete \(shown.count) completed reminder\(shown.count == 1 ? "" : "s")?",
                            isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { shown.forEach(delete) }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", color: nil, isSelected: navigation.selectedCategory == nil) {
                    navigation.selectedCategory = nil
                }
                ForEach(categories) { category in
                    chip(category.name, color: category.color.color,
                         isSelected: navigation.selectedCategory == category.name) {
                        navigation.selectedCategory = category.name
                    }
                }
            }
            .padding(.vertical, 4)
        }
        // Line the first chip up with the reminder cards, but let chips scroll out to the screen edge.
        .scrollClipDisabled()
    }

    private func chip(_ title: String, color: Color?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 6) {
                if let color {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : .primary)
            .background(isSelected ? AnyShapeStyle(color ?? .accentColor) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                        in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var emptyState: some View {
        let category = navigation.selectedCategory
        switch kind {
        case .active:
            ContentUnavailableView {
                Label("No Reminders", systemImage: "bell.slash")
            } description: {
                Text(category.map { "Nothing coming up in \($0)." } ?? "Tap + to add a reminder.")
            }
        case .completed:
            ContentUnavailableView {
                Label("Nothing Completed", systemImage: "checkmark.circle")
            } description: {
                Text("Reminders you finish will show up here.")
            }
        }
    }

    private var notificationsDeniedBanner: some View {
        HStack {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
            Text("Notifications are off. Remder can't alert you.")
                .font(.footnote)
            Spacer()
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.footnote.bold())
        }
    }

    private func toggleComplete(_ reminder: Reminder) {
        withAnimation {
            if reminder.isCompleted {
                NotificationManager.shared.uncomplete(reminder)
            } else {
                NotificationManager.shared.complete(reminder)
            }
            try? modelContext.save()
        }
    }

    private func delete(_ reminder: Reminder) {
        NotificationManager.shared.cancel(for: reminder)
        modelContext.delete(reminder)
        try? modelContext.save()
    }
}

/// Eases a tab's content in when you switch to it (fade, slight rise, soft blur) instead of
/// the instant swap, similar to Apple's own apps. Driven by the selection because TabView keeps
/// both tabs loaded, so onAppear doesn't fire on every switch.
private struct TabEntrance: ViewModifier {
    let isSelected: Bool
    @State private var isShown = true

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown ? 0 : 14)
            .blur(radius: isShown ? 0 : 6)
            .onChange(of: isSelected) { _, selected in
                guard selected else { return }
                // Draw one frame hidden, then ease in. (Resetting and animating in the same
                // update gets coalesced into no change at all.)
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { isShown = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    withAnimation(.smooth(duration: 0.4)) { isShown = true }
                }
            }
    }
}
