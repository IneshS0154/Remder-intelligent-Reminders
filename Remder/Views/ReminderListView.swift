import SwiftUI
import SwiftData

struct ReminderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reminder.dueDate) private var reminders: [Reminder]

    @State private var selectedCategory: String? = nil
    @State private var showingAddSheet = false
    @State private var editingReminder: Reminder?

    private var categories: [String] {
        Array(Set(reminders.map(\.category))).sorted()
    }

    private var filteredReminders: [Reminder] {
        guard let selectedCategory else { return reminders }
        return reminders.filter { $0.category == selectedCategory }
    }

    private var activeReminders: [Reminder] {
        filteredReminders.filter { !$0.isCompleted }
    }

    private var completedReminders: [Reminder] {
        filteredReminders.filter(\.isCompleted)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !categories.isEmpty {
                    categoryFilterBar
                }

                List {
                    Section("Active") {
                        if activeReminders.isEmpty {
                            Text("No active reminders")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(activeReminders) { reminder in
                            ReminderRowView(reminder: reminder) {
                                toggleComplete(reminder)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editingReminder = reminder }
                            .swipeActions {
                                Button(role: .destructive) { delete(reminder) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Section("Completed") {
                        if completedReminders.isEmpty {
                            Text("No completed reminders")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(completedReminders) { reminder in
                            ReminderRowView(reminder: reminder) {
                                toggleComplete(reminder)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editingReminder = reminder }
                            .swipeActions {
                                Button(role: .destructive) { delete(reminder) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Remder")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                ReminderFormView(reminder: nil)
            }
            .sheet(item: $editingReminder) { reminder in
                ReminderFormView(reminder: reminder)
            }
            .task {
                await NotificationManager.shared.requestAuthorizationIfNeeded()
            }
            .onAppear(perform: handlePendingDeepLink)
            .onChange(of: DeepLinkRouter.shared.pendingReminderID) {
                handlePendingDeepLink()
            }
        }
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Button("All") { selectedCategory = nil }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(selectedCategory == nil ? Color.accentColor.opacity(0.2) : .secondary.opacity(0.15), in: Capsule())
                    .buttonStyle(.plain)

                ForEach(categories, id: \.self) { category in
                    Button(category) { selectedCategory = category }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(selectedCategory == category ? Color.accentColor.opacity(0.2) : .secondary.opacity(0.15), in: Capsule())
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func toggleComplete(_ reminder: Reminder) {
        reminder.isCompleted.toggle()
        if reminder.isCompleted {
            reminder.completedDate = .now
            NotificationManager.shared.cancel(for: reminder)
        } else {
            reminder.completedDate = nil
            NotificationManager.shared.schedule(for: reminder)
        }
        try? modelContext.save()
    }

    private func delete(_ reminder: Reminder) {
        NotificationManager.shared.cancel(for: reminder)
        modelContext.delete(reminder)
        try? modelContext.save()
    }

    private func handlePendingDeepLink() {
        guard let id = DeepLinkRouter.shared.pendingReminderID else { return }
        if let match = reminders.first(where: { $0.id == id }) {
            editingReminder = match
        }
        DeepLinkRouter.shared.pendingReminderID = nil
    }
}
