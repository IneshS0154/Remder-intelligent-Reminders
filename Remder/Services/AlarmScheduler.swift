import Foundation
import SwiftUI
#if os(iOS)
import ActivityKit
import AlarmKit
#endif

/// Schedules full-screen alarms (AlarmKit) for reminders that ask for one. An alarm rings like
/// the Clock app, even in Silent mode or a Focus, and offers Snooze. The reminder's ID is the
/// alarm ID, so each reminder has at most one alarm.
final class AlarmScheduler {
    static let shared = AlarmScheduler()

    private init() {}

    #if os(iOS)
    private typealias Configuration = AlarmManager.AlarmConfiguration<ReminderAlarmMetadata>

    var isAuthorized: Bool { AlarmManager.shared.authorizationState == .authorized }
    var isDenied: Bool { AlarmManager.shared.authorizationState == .denied }

    /// Asks for permission the first time; returns whether alarms may be scheduled.
    func requestAuthorization() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized: return true
        case .denied: return false
        default:
            do {
                return try await AlarmManager.shared.requestAuthorization() == .authorized
            } catch {
                #if DEBUG
                print("Remder Alarm: authorization request failed: \(error)")
                #endif
                return false
            }
        }
    }

    /// Replaces the reminder's alarm to match its current settings (used after edits).
    func sync(_ reminder: Reminder) {
        cancel(reminderID: reminder.id)
        schedule(reminder)
    }

    /// Makes alarms match all reminders without disturbing one that is ringing or snoozed.
    func resync(reminders: [Reminder]) {
        guard let alarms = try? AlarmManager.shared.alarms else { return }
        let existing = Dictionary(alarms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let wanted = reminders.filter(wantsAlarm)
        let wantedIDs = Set(wanted.map(\.id))

        for id in existing.keys where !wantedIDs.contains(id) {
            try? AlarmManager.shared.cancel(id: id)
        }
        for reminder in wanted {
            if let alarm = existing[reminder.id] {
                // Leave ringing or snoozed alarms alone; refresh scheduled ones only if the time changed.
                guard alarm.state == .scheduled, alarm.schedule != schedule(for: reminder) else { continue }
                try? AlarmManager.shared.cancel(id: reminder.id)
            }
            schedule(reminder)
        }
    }

    func cancel(reminderID: UUID) {
        try? AlarmManager.shared.cancel(id: reminderID)
    }

    // MARK: - Private

    private func wantsAlarm(_ reminder: Reminder) -> Bool {
        reminder.alarmEnabled && !reminder.isCompleted && schedule(for: reminder) != nil
    }

    private func schedule(_ reminder: Reminder) {
        guard isAuthorized, wantsAlarm(reminder), let schedule = schedule(for: reminder) else { return }

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: reminder.title),
            secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz"),
            secondaryButtonBehavior: .countdown
        )
        let attributes = AlarmAttributes<ReminderAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: .init(title: "Snoozed")),
            metadata: ReminderAlarmMetadata(reminderID: reminder.id.uuidString, title: reminder.title),
            tintColor: reminder.priority.color
        )
        let configuration = Configuration(
            countdownDuration: .init(preAlert: nil, postAlert: TimeInterval(AppSettings.snoozeMinutes * 60)),
            schedule: schedule,
            attributes: attributes,
            sound: AppSettings.sound.fileName.map { .named($0) } ?? .default
        )
        let id = reminder.id
        let title = reminder.title
        Task {
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            } catch {
                #if DEBUG
                print("Remder Alarm: couldn't schedule alarm for \"\(title)\": \(error)")
                #endif
            }
        }
    }

    /// Daily, weekly and "on these weekdays" reminders use a repeating alarm; everything else
    /// rings once at its next due time and is rescheduled each time the app syncs.
    /// Location reminders have no time, so they never get an alarm.
    private func schedule(for reminder: Reminder) -> Alarm.Schedule? {
        guard !reminder.isLocationBased else { return nil }
        let calendar = Calendar.current
        let due = reminder.upcomingDueDate
        let time = Alarm.Schedule.Relative.Time(
            hour: calendar.component(.hour, from: due),
            minute: calendar.component(.minute, from: due)
        )
        switch reminder.repeatFrequency {
        case .none, .monthly:
            return due > .now ? .fixed(due) : nil
        case .custom:
            // Every week on the same days, forever: AlarmKit can repeat that itself.
            if let rule = reminder.repeatRule, rule.frequency == .weekly, rule.interval == 1, rule.end == .never,
               !rule.everyWeekdays.isEmpty, rule.everyWeekdays.count == rule.weekdays.count {
                return .relative(.init(time: time, repeats: .weekly(rule.everyWeekdays)))
            }
            return due > .now ? .fixed(due) : nil
        case .daily:
            return .relative(.init(time: time, repeats: .weekly(Locale.Weekday.allWeekdays)))
        case .weekly:
            let weekday = Locale.Weekday.allWeekdays[calendar.component(.weekday, from: due) - 1]
            return .relative(.init(time: time, repeats: .weekly([weekday])))
        }
    }
    #else
    var isAuthorized: Bool { false }
    var isDenied: Bool { false }
    func requestAuthorization() async -> Bool { false }
    func sync(_ reminder: Reminder) {}
    func resync(reminders: [Reminder]) {}
    func cancel(reminderID: UUID) {}
    #endif
}

#if os(iOS)
private extension Locale.Weekday {
    static var allWeekdays: [Locale.Weekday] { ordered }
}
#endif
