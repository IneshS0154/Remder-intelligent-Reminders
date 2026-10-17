import SwiftUI

struct ReminderRowView: View {
    let reminder: Reminder
    /// Color of the reminder's category, or nil if it has none (or the category was removed).
    var categoryColor: Color? = nil
    let onToggleComplete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onToggleComplete) {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(reminder.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reminder.isCompleted ? "Mark \(reminder.title) as not done" : "Complete \(reminder.title)")

            Circle()
                .fill(reminder.priority.color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.body)
                    .strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? .secondary : .primary)

                HStack(spacing: 6) {
                    if let location = reminder.location {
                        HStack(spacing: 3) {
                            Image(systemName: location.trigger == .arriving ? "location.fill" : "location.north.line.fill")
                                .font(.caption2)
                            Text(location.summary)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.teal)
                    } else {
                    TimelineView(.everyMinute) { _ in
                        HStack(spacing: 4) {
                            if reminder.isOverdue {
                                Text("Overdue")
                                    .font(.caption.bold())
                            }
                            Text(reminder.dueDate, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                        }
                        .foregroundStyle(reminder.isOverdue ? .red : .secondary)
                    }
                    }

                    if reminder.alarmEnabled {
                        Image(systemName: "alarm.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if reminder.note != nil {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if reminder.repeatFrequency != .none, !reminder.isCompleted {
                        let streak = StreakCalculator.stats(for: reminder).current
                        if streak >= 2 {
                            HStack(spacing: 1) {
                                Image(systemName: "flame.fill")
                                Text("\(streak)")
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("\(streak) in a row")
                        }
                    }

                    if reminder.repeatFrequency != .none {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(reminder.repeatSummary)
                    }

                    if !reminder.category.isEmpty {
                        Text(reminder.category)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(categoryColor ?? .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((categoryColor ?? .secondary).opacity(0.15), in: Capsule())
                    }
                }
            }

            Spacer()
        }
    }
}
