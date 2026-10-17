import SwiftData
import SwiftUI

/// The Notes section: standalone notes that can be attached to reminders.
struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var navigation
    @Query(sort: \Note.updatedDate, order: .reverse) private var notes: [Note]

    @State private var path: [Note] = []
    @State private var searchText = ""
    @State private var deletingNote: Note?

    private var filtered: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(filtered) { note in
                    NavigationLink(value: note) {
                        NoteRow(note: note)
                    }
                    .swipeActions {
                        Button(role: .destructive) { deletingNote = note } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .contentMargins(.top, 4, for: .scrollContent)
            .overlay {
                if notes.isEmpty {
                    ContentUnavailableView {
                        Label("No Notes", systemImage: "note.text")
                    } description: {
                        Text("Tap the compose button to write a note, then attach it to a reminder for all the details.")
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .searchable(text: $searchText, prompt: "Search notes")
            .sectionNavigationBar(title: "Notes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: createNote) { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New Note")
                }
            }
            .navigationDestination(for: Note.self) { note in
                NoteEditorView(note: note, discardIfEmpty: true)
                    .onAppear { navigation.isShowingDetail = true }
                    .onDisappear { navigation.isShowingDetail = false }
            }
            .confirmationDialog(
                "Delete \"\(deletingNote?.displayTitle ?? "")\"?",
                isPresented: Binding(get: { deletingNote != nil }, set: { if !$0 { deletingNote = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Note", role: .destructive) {
                    guard let note = deletingNote else { return }
                    modelContext.delete(note)
                    try? modelContext.save()
                }
            } message: {
                if let count = deletingNote?.reminders.count, count > 0 {
                    Text("It will be removed from \(count) reminder\(count == 1 ? "" : "s"). The reminders are kept.")
                }
            }
        }
    }

    private func createNote() {
        let note = Note()
        modelContext.insert(note)
        path.append(note)
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.displayTitle)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(note.updatedDate, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
                if !note.preview.isEmpty {
                    Text(note.preview)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.subheadline)

            if !note.reminders.isEmpty {
                Label("\(note.reminders.count) reminder\(note.reminders.count == 1 ? "" : "s")", systemImage: "bell.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Edits a note. Typing goes into local state and is written back shortly after you pause
/// (and when you leave), so saving never interrupts the keyboard.
struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    let note: Note
    /// Like Notes.app: a note left empty (and unused) is discarded when you leave it.
    var discardIfEmpty = false

    @State private var title: String
    @State private var noteBody: String
    @State private var pendingSave: Task<Void, Never>?
    @FocusState private var focus: Field?

    private enum Field { case title, body }

    init(note: Note, discardIfEmpty: Bool = false) {
        self.note = note
        self.discardIfEmpty = discardIfEmpty
        _title = State(initialValue: note.title)
        _noteBody = State(initialValue: note.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $title)
                .font(.title2.bold())
                .focused($focus, equals: .title)
                .submitLabel(.next)
                .onSubmit { focus = .body }
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Text(note.updatedDate, format: .dateTime.day().month(.wide).year().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            // The system text view: smooth typing and scrolling however long the note gets.
            TextEditor(text: $noteBody)
                .font(.body)
                .focused($focus, equals: .body)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .padding(.horizontal, 15)
                .overlay(alignment: .topLeading) {
                    if noteBody.isEmpty {
                        Text("Write the details…")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !note.reminders.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("Attached to") {
                            ForEach(note.reminders.sorted { $0.dueDate < $1.dueDate }) { reminder in
                                Label {
                                    Text(reminder.title)
                                    Text(reminder.dueDate, format: .dateTime.weekday().month().day().hour().minute())
                                } icon: {
                                    Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "bell.fill")
                                }
                            }
                        }
                    } label: {
                        Label("\(note.reminders.count)", systemImage: "bell.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("Attached to \(note.reminders.count) reminders")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if focus != nil {
                    Button("Done") { focus = nil }
                }
            }
        }
        .onAppear {
            if note.isEmpty { focus = .title }
        }
        .onChange(of: title) { scheduleSave() }
        .onChange(of: noteBody) { scheduleSave() }
        .onChange(of: scenePhase) {
            if scenePhase != .active { saveNow() }
        }
        .onDisappear {
            saveNow()
            if discardIfEmpty && note.isEmpty && note.reminders.isEmpty {
                modelContext.delete(note)
                try? modelContext.save()
            }
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        pendingSave?.cancel()
        guard note.title != title || note.body != noteBody else { return }
        note.title = title
        note.body = noteBody
        note.updatedDate = .now
        try? modelContext.save()
    }
}

/// Sheet for writing a new note from the reminder form. Nothing is saved until "Save".
struct NewNoteSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let onSave: (Note) -> Void

    @State private var title = ""
    @State private var noteBody = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                    .font(.headline)
                    .focused($titleFocused)
                TextField("Write the details…", text: $noteBody, axis: .vertical)
                    .lineLimit(8...)
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let note = Note(title: title.trimmingCharacters(in: .whitespacesAndNewlines), body: noteBody)
                        modelContext.insert(note)
                        try? modelContext.save()
                        onSave(note)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { titleFocused = true }
        }
    }
}
