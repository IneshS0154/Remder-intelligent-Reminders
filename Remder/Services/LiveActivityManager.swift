import Foundation
#if os(iOS)
import ActivityKit
#endif

/// Schedules the Dynamic Island / Lock Screen countdown that leads up to a reminder.
///
/// Activities are scheduled with a start date, so the system shows them at "due − lead time"
/// even if Remder isn't running. They stay (showing "Now" once due) until the reminder is
/// completed from the Live Activity, the notification, or the app.
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private init() {}

    #if os(iOS)
    private typealias ReminderActivity = Activity<ReminderActivityAttributes>

    /// False when the user has turned off Live Activities for Remder in Settings.
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Makes the reminder's Live Activity match its current settings.
    /// With `restart`, any existing activity is replaced even if it looks up to date (e.g. after an edit).
    func sync(_ reminder: Reminder, restart: Bool = false) {
        let existing = activities(for: reminder.id)
        let due = reminder.upcomingDueDate

        guard !reminder.isCompleted, reminder.liveActivityLeadMinutes > 0 else {
            end(existing)
            return
        }

        if !restart, let current = existing.first {
            // Already counting down to the right time, or showing "Now" for an occurrence the user
            // hasn't dealt with yet; leave it alone.
            let shownDue = current.content.state.dueDate
            if shownDue == due || shownDue <= .now { return }
        }

        end(existing)
        // A one-off reminder that's already due gets no new countdown.
        guard due > .now else { return }
        request(for: reminder, due: due)
    }

    func resync(reminders: [Reminder]) {
        let known = Set(reminders.map(\.id.uuidString))
        end(ReminderActivity.activities.filter { !known.contains($0.attributes.reminderID) })
        reminders.forEach { sync($0) }
    }

    func end(reminderID: UUID) {
        end(activities(for: reminderID))
    }

    /// Points the countdown at the snoozed time, starting one if the reminder has a lead time but no activity yet.
    func snooze(_ reminder: Reminder, until date: Date) {
        guard reminder.liveActivityLeadMinutes > 0 else { return }
        let existing = activities(for: reminder.id)
        guard !existing.isEmpty else {
            request(for: reminder, due: date)
            return
        }
        let content = ActivityContent(state: ReminderActivityAttributes.ContentState(dueDate: date, startDate: .now), staleDate: date)
        for activity in existing {
            Task { await activity.update(content) }
        }
    }

    // MARK: - Private

    private func activities(for reminderID: UUID) -> [ReminderActivity] {
        ReminderActivity.activities.filter {
            $0.attributes.reminderID == reminderID.uuidString
                && $0.activityState != .ended && $0.activityState != .dismissed
        }
    }

    private func end(_ activities: [ReminderActivity]) {
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func request(for reminder: Reminder, due: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log("not starting countdown for \"\(reminder.title)\": Live Activities are turned off for Remder")
            return
        }

        let attributes = ReminderActivityAttributes(
            reminderID: reminder.id.uuidString,
            title: reminder.title,
            notes: reminder.notes,
            priority: reminder.priority.rawValue,
            category: reminder.category.isEmpty ? nil : reminder.category
        )
        let start = due.addingTimeInterval(-TimeInterval(reminder.liveActivityLeadMinutes * 60))
        // Going stale at the due time flips the countdown to "Now".
        let content = ActivityContent(
            state: ReminderActivityAttributes.ContentState(dueDate: due, startDate: start),
            staleDate: due
        )

        do {
            if start > .now {
                let alert = AlertConfiguration(
                    title: "\(reminder.title)",
                    body: "Due in \(reminder.liveActivityLeadMinutes) min",
                    sound: alertSound()
                )
                let activity = try ReminderActivity.request(
                    attributes: attributes, content: content,
                    style: .standard, alertConfiguration: alert, start: start
                )
                log("scheduled countdown for \"\(reminder.title)\" to start \(start) (\(activity.activityState))")
            } else {
                // Already inside the lead window: show it right away.
                let activity = try ReminderActivity.request(attributes: attributes, content: content, style: .standard)
                log("started countdown for \"\(reminder.title)\" now (\(activity.activityState))")
            }
        } catch {
            log("couldn't start countdown for \"\(reminder.title)\": \(error)")
        }
    }

    private func log(_ message: String) {
        #if DEBUG
        print("Remder Live Activity: \(message)")
        #endif
    }

    private func alertSound() -> AlertConfiguration.AlertSound {
        AppSettings.sound.fileName.map { .named($0) } ?? .default
    }
    #else
    var areActivitiesEnabled: Bool { false }
    func sync(_ reminder: Reminder, restart: Bool = false) {}
    func resync(reminders: [Reminder]) {}
    func end(reminderID: UUID) {}
    func snooze(_ reminder: Reminder, until date: Date) {}
    #endif
}
