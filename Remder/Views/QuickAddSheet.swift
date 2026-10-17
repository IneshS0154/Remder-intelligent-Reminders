import SwiftData
import SwiftUI

/// Type a reminder in one line ("Call mom tomorrow 5pm #Work !high") and add it with Return.
/// Chips show what was understood; "Edit Details" opens the full form pre-filled.
/// With Apple Intelligence, looser phrasing ("after work on Friday") is understood too.
struct QuickAddSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\ReminderCategory.sortOrder), SortDescriptor(\ReminderCategory.createdDate)])
    private var categories: [ReminderCategory]

    /// Category being viewed, used when none is typed.
    let defaultCategory: String?
    /// Called with the parsed values when the user wants the full form.
    let onEditDetails: (ParsedReminder) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    /// Apple Intelligence's reading of `aiText`; used while it still matches what's typed.
    @State private var aiResult: ParsedReminder?
    @State private var aiText = ""
    @State private var aiWorking = false
    @State private var isSaving = false
    private let aiEnabled = AIQuickAdd.isEnabled

    private var aiApplied: Bool { aiResult != nil && aiText == text && !text.isEmpty }

    private var parsed: ParsedReminder {
        resolve(text, ai: aiText == text ? aiResult : nil)
    }

    private func resolve(_ text: String, ai: ParsedReminder?) -> ParsedReminder {
        var result = QuickAddParser.parse(text, categories: categories.map(\.name))
        if let ai { result = QuickAdd.merge(parsed: result, ai: ai) }
        if result.category == nil, let defaultCategory { result.category = defaultCategory }
        return result
    }

    private var canAdd: Bool { !parsed.title.isEmpty && !isSaving }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField(aiEnabled ? "Pick up dry cleaning after work Friday" : "Call mom tomorrow 5pm #Work !high",
                          text: $text, axis: .vertical)
                    .font(.title3)
                    .lineLimit(1...3)
                    .focused($focused)
                    .accessibilityIdentifier("quickAdd.field")
                    .submitLabel(.done)
                    .onSubmit(add)
                    .onChange(of: text) { _, newValue in
                        // Return inserts a newline in a vertical field; treat it as "Add".
                        if newValue.contains("\n") {
                            text = newValue.replacingOccurrences(of: "\n", with: "")
                            add()
                        }
                    }

                Button(action: add) {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up").font(.headline.weight(.bold))
                        }
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(!canAdd)
                .accessibilityLabel("Add Reminder")
            }

            chips

            HStack {
                Button("Edit Details", systemImage: "slider.horizontal.3") {
                    onEditDetails(parsed)
                    dismiss()
                }
                .font(.subheadline.weight(.medium))
                Spacer()
                if aiEnabled {
                    Label("Apple Intelligence", systemImage: "sparkles")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(aiApplied ? AnyShapeStyle(Self.intelligenceGradient) : AnyShapeStyle(.tertiary))
                        .symbolEffect(.pulse, isActive: aiWorking || isSaving)
                        .animation(.easeInOut, value: aiApplied)
                } else {
                    Text("Try #category, !high, alarm, every day")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(20)
        .presentationDetents([.height(210)])
        .presentationBackgroundInteraction(.enabled)
        .onAppear { focused = true }
        .task(id: text) { await readWithIntelligence() }
    }

    private static let intelligenceGradient = LinearGradient(
        colors: [.orange, .pink, .purple, .blue], startPoint: .leading, endPoint: .trailing
    )

    /// Asks Apple Intelligence once typing pauses; the regex parser keeps the chips live meanwhile.
    private func readWithIntelligence() async {
        guard aiEnabled else { return }
        let current = text
        guard !current.trimmingCharacters(in: .whitespaces).isEmpty else {
            aiResult = nil
            aiWorking = false
            return
        }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        aiWorking = true
        let result: ParsedReminder?
        do {
            result = try await AIQuickAdd.parse(current, categories: categories.map(\.name), now: .now)
        } catch {
            #if DEBUG
            print("Quick add: Apple Intelligence failed: \(error)")
            #endif
            result = nil
        }
        guard !Task.isCancelled else { return }
        aiResult = result
        aiText = current
        aiWorking = false
    }

    private var chips: some View {
        let result = parsed
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if result.location == nil {
                    chip(ReminderFormView.dueSummary(result.dueDate).components(separatedBy: " · ").first ?? "",
                         icon: "calendar", tint: result.hasExplicitDate ? .blue : .secondary)
                }
                if let repeatLabel = result.repeatLabel {
                    chip(repeatLabel, icon: "repeat", tint: .blue)
                }
                if let location = result.location {
                    chip(location.summary, icon: "location.fill", tint: .teal)
                }
                if let category = result.category, !category.isEmpty {
                    chip(result.isNewCategory ? "\(category) (new)" : category, icon: "number",
                         tint: categories.first { $0.name == category }?.color.color ?? .purple)
                }
                if let priority = result.priority {
                    chip(priority.label, icon: "exclamationmark", tint: priority.color)
                }
                if result.alarm {
                    chip("Alarm", icon: "alarm.fill", tint: .orange)
                }
                if let lead = result.leadMinutes {
                    chip(ReminderFormView.leadTimeLabel(lead) + " countdown", icon: "timer", tint: .indigo)
                }
            }
        }
        .scrollClipDisabled()
        .animation(.snappy, value: result.dueDate)
    }

    private func chip(_ title: String, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func add() {
        guard canAdd else { return }
        // Save exactly what was submitted, even if the field changes while Apple Intelligence reads it.
        // Return can arrive as both a newline and a submit; `isSaving` makes the second a no-op.
        let submitted = text
        isSaving = true
        Task {
            defer { isSaving = false }
            var ai = aiText == submitted ? aiResult : nil
            if aiEnabled, ai == nil {
                ai = try? await AIQuickAdd.parse(submitted, categories: categories.map(\.name), now: .now)
            }
            let result = resolve(submitted, ai: ai)
            guard !result.title.isEmpty else { return }
            QuickAdd.save(result, categories: categories, in: modelContext)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if text == submitted { text = "" }
            focused = true  // Return dismisses the keyboard; stay ready for the next one.
        }
    }
}
