import Foundation

/// Streaks and completion stats for repeating reminders, derived from their `Completion` history.
struct StreakStats {
    /// Occurrences completed in a row, counting back from the most recent one that's come due.
    var current = 0
    var best = 0
    /// Share of occurrences in the last 30 days that were completed; nil if none were due yet.
    var rate30Days: Double?
    var totalCompleted = 0
    /// Start-of-day dates with at least one completion (for the heatmap).
    var completedDays: Set<Date> = []
}

enum StreakCalculator {
    /// How many past occurrences to look at at most (about three years of daily reminders).
    private static let maxOccurrences = 1100

    static func stats(for reminder: Reminder, now: Date = .now) -> StreakStats {
        let calendar = Calendar.current
        var stats = StreakStats()
        let completions = reminder.completions
        stats.totalCompleted = completions.count
        stats.completedDays = Set(completions.map { calendar.startOfDay(for: $0.completedAt) })

        guard reminder.repeatComponent != nil else { return stats }
        let occurrences = pastOccurrences(of: reminder, now: now)
        guard !occurrences.isEmpty else { return stats }

        let doneDays = Set(completions.map { calendar.startOfDay(for: $0.occurrenceDate) })
        let done = occurrences.map { doneDays.contains(calendar.startOfDay(for: $0)) }

        // Best streak: longest run of completed occurrences (oldest → newest).
        var run = 0
        for isDone in done {
            run = isDone ? run + 1 : 0
            stats.best = max(stats.best, run)
        }

        // Current streak: count back from the newest. The newest occurrence is still "open" until
        // the next one comes due, so an unfinished one there doesn't break the streak.
        var index = done.count - 1
        if index >= 0, !done[index] { index -= 1 }
        while index >= 0, done[index] {
            stats.current += 1
            index -= 1
        }

        let monthAgo = now.addingTimeInterval(-30 * 24 * 3600)
        let recent = zip(occurrences, done).filter { $0.0 >= monthAgo }
        // Leave out the open occurrence if it isn't done yet.
        let counted = recent.last.map { $0.1 } == false ? recent.dropLast() : recent[...]
        if !counted.isEmpty {
            stats.rate30Days = Double(counted.filter(\.1).count) / Double(counted.count)
        }
        return stats
    }

    /// Occurrences that have come due, oldest first: back from the current due date to when the
    /// reminder was created (or its first completion), and forward to now for missed ones.
    private static func pastOccurrences(of reminder: Reminder, now: Date) -> [Date] {
        guard let component = reminder.repeatComponent else { return [] }
        let calendar = Calendar.current
        let firstCompletion = reminder.completions.map(\.occurrenceDate).min() ?? reminder.createdDate
        let start = calendar.startOfDay(for: min(reminder.createdDate, firstCompletion))

        if reminder.repeatFrequency == .custom, let rule = reminder.repeatRule {
            // Step back from the due date in whole repeat periods (keeping "every 2 weeks" in
            // phase), then let the rule list its occurrences up to now.
            var anchor = reminder.dueDate
            var steps = 0
            while anchor > start, steps < maxOccurrences,
                  let earlier = calendar.date(byAdding: rule.unit, value: -rule.interval, to: anchor) {
                anchor = earlier
                steps += 1
            }
            // Everything that has come due: past occurrences plus missed ones after the due date.
            return Array(rule.recurrences(of: anchor, in: start..<now.addingTimeInterval(1)).prefix(maxOccurrences))
        }

        var dates: [Date] = []
        // Backward from the due date (occurrences already completed and moved past).
        var step = 1
        while dates.count < maxOccurrences,
              let date = calendar.date(byAdding: component, value: -step, to: reminder.dueDate),
              date >= start {
            dates.append(date)
            step += 1
        }
        dates.reverse()
        // The due date and anything after it that has already come due (missed occurrences).
        step = 0
        while dates.count < maxOccurrences,
              let date = calendar.date(byAdding: component, value: step, to: reminder.dueDate),
              date <= now {
            dates.append(date)
            step += 1
        }
        return dates
    }
}
