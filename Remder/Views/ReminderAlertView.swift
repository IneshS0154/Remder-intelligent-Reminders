import SwiftUI
import SwiftData

/// Shown when a reminder fires (in the foreground) or its notification is tapped.
struct ReminderAlertView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let reminder: Reminder

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(reminder.priority.color)
                .symbolEffect(.bounce, options: .repeat(2))
                .padding(.top, 32)

            VStack(spacing: 8) {
                Text(reminder.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Group {
                    if let location = reminder.location {
                        Label(location.summary, systemImage: "location.fill")
                    } else {
                        Text(reminder.dueDate, format: .dateTime.weekday().month().day().hour().minute())
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let notes = reminder.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal)

            if let note = reminder.note, !note.isEmpty {
                noteCard(note)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    NotificationManager.shared.complete(reminder)
                    try? modelContext.save()
                    dismiss()
                } label: {
                    Label(reminder.repeats || reminder.location?.repeats == true ? "Done for Now" : "Mark Complete",
                          systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 10) {
                    Button {
                        snooze(.minutes)
                    } label: {
                        Label(SnoozeOption.minutes.title(minutes: NotificationManager.snoozeMinutes), systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                    }

                    // The other snooze choices: 1 hour, this evening, tomorrow morning.
                    Menu {
                        ForEach(SnoozeOption.allCases.filter { $0 != .minutes }) { option in
                            Button {
                                snooze(option)
                            } label: {
                                Label {
                                    Text(option.title(minutes: NotificationManager.snoozeMinutes))
                                    Text(option.date(minutes: NotificationManager.snoozeMinutes)
                                        .formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                                } icon: {
                                    Image(systemName: option.systemImage)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 24)
                            .frame(maxHeight: .infinity)
                    }
                    .accessibilityLabel("More snooze options")
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.bordered)
                .fixedSize(horizontal: false, vertical: true)

                Button("Dismiss") { dismiss() }
                    .padding(.top, 4)
            }
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .presentationDetents(reminder.note == nil ? [.medium, .large] : [.large])
    }

    private func snooze(_ option: SnoozeOption) {
        NotificationManager.shared.snooze(reminder, option: option)
        dismiss()
    }

    private func noteCard(_ note: Note) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Label(note.displayTitle, systemImage: "note.text")
                    .font(.headline)
                    .foregroundStyle(.orange)
                if !note.body.isEmpty {
                    Text(note.body)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(maxHeight: 260)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }
}
