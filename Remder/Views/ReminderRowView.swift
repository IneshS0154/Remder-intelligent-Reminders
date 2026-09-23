import SwiftUI

struct ReminderRowView: View {
    let reminder: Reminder
    let onToggleComplete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleComplete) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(reminder.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Circle()
                .fill(priorityColor)
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.body)
                    .strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? .secondary : .primary)

                HStack(spacing: 6) {
                    Text(reminder.dueDate, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if reminder.repeatFrequency != .none {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(reminder.category)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
            }

            Spacer()
        }
    }

    private var priorityColor: Color {
        switch reminder.priority {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}
