import SwiftData
import SwiftUI

/// Streaks and stats: an overview, then a card per repeating reminder.
struct InsightsView: View {
    @Query private var reminders: [Reminder]
    @Query private var completions: [Completion]
    @Query private var categories: [ReminderCategory]

    private var repeating: [Reminder] {
        reminders
            .filter { $0.repeatFrequency != .none && !$0.isCompleted }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    summary

                    if repeating.isEmpty {
                        ContentUnavailableView {
                            Label("No Habits Yet", systemImage: "flame")
                        } description: {
                            Text("Make a reminder repeat daily, weekly or monthly to track its streak here.")
                        }
                        .padding(.top, 40)
                    } else {
                        Text("Repeating Reminders")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)
                            .padding(.bottom, -12)

                        ForEach(repeating) { reminder in
                            HabitCard(
                                reminder: reminder,
                                stats: StreakCalculator.stats(for: reminder),
                                tint: categories.first { $0.name == reminder.category }?.color.color ?? reminder.priority.color
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .sectionNavigationBar(title: "Insights")
        }
    }

    private var summary: some View {
        let thisWeek = completions.filter { $0.completedAt >= weekStart }.count
        let onTime = completions.isEmpty ? nil : Double(completions.filter(\.isOnTime).count) / Double(completions.count)
        let bestStreak = repeating.map { StreakCalculator.stats(for: $0).best }.max() ?? 0

        return HStack(spacing: 12) {
            tile(value: "\(thisWeek)", label: "Done this week", icon: "checkmark.circle.fill", tint: .green)
            tile(value: onTime.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", label: "On time", icon: "clock.fill", tint: .blue)
            tile(value: "\(bestStreak)", label: "Best streak", icon: "flame.fill", tint: .orange)
        }
    }

    private func tile(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct HabitCard: View {
    let reminder: Reminder
    let stats: StreakStats
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(reminder.repeatSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(stats.current > 0 ? .orange : .secondary)
                    Text("\(stats.current)")
                        .font(.title2.bold())
                        .monospacedDigit()
                }
            }

            HStack(spacing: 0) {
                metric("Best", "\(stats.best)")
                metric("Last 30 days", stats.rate30Days.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                metric("Total", "\(stats.totalCompleted)")
            }

            Heatmap(completedDays: stats.completedDays, tint: tint)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The last 12 weeks as a grid of days (columns are weeks), filled on days with a completion.
private struct Heatmap: View {
    let completedDays: Set<Date>
    let tint: Color

    private static let weeks = 12

    private var columns: [[Date?]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return (0..<Self.weeks).reversed().map { weeksAgo in
            let start = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeekStart) ?? thisWeekStart
            return (0..<7).map { day in
                let date = calendar.date(byAdding: .day, value: day, to: start)
                return date.flatMap { $0 <= today ? $0 : nil }
            }
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(for: week[index]))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(completedDays.count) days with completions in the last 12 weeks")
    }

    private func color(for date: Date?) -> Color {
        guard let date else { return .clear }
        return completedDays.contains(date) ? tint : Color(.tertiarySystemFill)
    }
}
