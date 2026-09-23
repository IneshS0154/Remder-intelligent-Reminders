import SwiftUI
import SwiftData

struct ReminderFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingReminders: [Reminder]

    let reminder: Reminder?

    @State private var title: String
    @State private var notes: String
    @State private var dueDate: Date
    @State private var priority: Priority
    @State private var category: String
    @State private var repeatFrequency: RepeatFrequency

    init(reminder: Reminder?) {
        self.reminder = reminder
        _title = State(initialValue: reminder?.title ?? "")
        _notes = State(initialValue: reminder?.notes ?? "")
        _dueDate = State(initialValue: reminder?.dueDate ?? Date().addingTimeInterval(3600))
        _priority = State(initialValue: reminder?.priority ?? .medium)
        _category = State(initialValue: reminder?.category ?? "General")
        _repeatFrequency = State(initialValue: reminder?.repeatFrequency ?? .none)
    }

    private var existingCategories: [String] {
        Array(Set(existingReminders.map(\.category))).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Due") {
                    DatePicker("Date & Time", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Category") {
                    TextField("Category", text: $category)
                    if !existingCategories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(existingCategories, id: \.self) { cat in
                                    Button(cat) { category = cat }
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.secondary.opacity(0.15), in: Capsule())
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                Section("Repeat") {
                    Picker("Repeat", selection: $repeatFrequency) {
                        ForEach(RepeatFrequency.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    if repeatFrequency == .monthly {
                        Text("Reminders set on the 29th–31st may be skipped in shorter months.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(reminder == nil ? "New Reminder" : "Edit Reminder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCategory = trimmedCategory.isEmpty ? "General" : trimmedCategory

        let target: Reminder
        if let reminder {
            target = reminder
            target.title = title
            target.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            target.dueDate = dueDate
            target.priority = priority
            target.category = finalCategory
            target.repeatFrequency = repeatFrequency
        } else {
            target = Reminder(
                title: title,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                dueDate: dueDate,
                priority: priority,
                category: finalCategory,
                repeatFrequency: repeatFrequency
            )
            modelContext.insert(target)
        }

        try? modelContext.save()
        NotificationManager.shared.reschedule(for: target)
        dismiss()
    }
}
