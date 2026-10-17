import Foundation
import SwiftData

/// One completed occurrence of a reminder. Recorded whenever a reminder is marked done
/// (from the app, a notification, the Live Activity or a widget) and used for streaks and stats.
@Model
final class Completion {
    /// The due time of the occurrence that was completed.
    var occurrenceDate: Date = Date.now
    var completedAt: Date = Date.now
    var reminder: Reminder?

    init(occurrenceDate: Date, completedAt: Date = .now) {
        self.occurrenceDate = occurrenceDate
        self.completedAt = completedAt
    }

    /// Done no later than an hour after it was due.
    var isOnTime: Bool {
        completedAt <= occurrenceDate.addingTimeInterval(3600)
    }
}
