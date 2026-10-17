import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

/// Home Screen and Lock Screen widgets showing upcoming reminders, read from the shared store.
struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpcomingReminders", provider: UpcomingProvider()) { entry in
            UpcomingWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Upcoming Reminders")
        .description("Your next reminders. Tap the circle to complete one.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

// MARK: - Timeline

/// A lightweight copy of a reminder, so the view doesn't touch SwiftData.
struct ReminderSnapshot: Identifiable, Hashable {
    let id: UUID
    let title: String
    let dueDate: Date
    let isOverdue: Bool
    let priority: Priority
    let categoryColor: Color?
    let repeats: Bool
}

struct UpcomingEntry: TimelineEntry {
    let date: Date
    let reminders: [ReminderSnapshot]
    /// Reminders due before the end of today (for the circular Lock Screen widget).
    let dueTodayCount: Int
}

struct UpcomingProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingEntry {
        UpcomingEntry(date: .now, reminders: Self.sample, dueTodayCount: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingEntry>) -> Void) {
        let now = Date.now
        // One entry now, then one at each of the next few due times so "next up" rolls forward
        // on its own. The app also reloads the timeline whenever reminders change.
        let upcomingTimes = loadReminders(now: now)
            .map(\.dueDate)
            .filter { $0 > now }
            .prefix(8)
        let entries = [entry(at: now)] + upcomingTimes.map { entry(at: $0.addingTimeInterval(1)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> UpcomingEntry {
        let reminders = loadReminders(now: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date)) ?? date
        return UpcomingEntry(
            date: date,
            reminders: Array(reminders.prefix(8)),
            dueTodayCount: reminders.filter { $0.dueDate < endOfDay }.count
        )
    }

    /// Active reminders: overdue ones first, then upcoming by time.
    private func loadReminders(now: Date) -> [ReminderSnapshot] {
        guard let container = try? SharedStore.makeContainer() else { return [] }
        let context = ModelContext(container)
        // Location reminders have no time to count down to, so they're left out.
        let reminders = ((try? context.fetch(FetchDescriptor<Reminder>(predicate: #Predicate { !$0.isCompleted }))) ?? [])
            .filter { !$0.isLocationBased }
        let categories = (try? context.fetch(FetchDescriptor<ReminderCategory>())) ?? []
        let colors = Dictionary(categories.map { ($0.name, $0.color.color) }, uniquingKeysWith: { first, _ in first })

        return reminders.map { reminder in
            let due = reminder.repeatFrequency == .none
                ? reminder.dueDate
                : (reminder.dueDate > now ? reminder.dueDate : reminder.nextOccurrence(after: now) ?? reminder.dueDate)
            return ReminderSnapshot(
                id: reminder.id,
                title: reminder.title,
                dueDate: due,
                isOverdue: reminder.repeatFrequency == .none && due < now,
                priority: reminder.priority,
                categoryColor: colors[reminder.category],
                repeats: reminder.repeatFrequency != .none
            )
        }
        .sorted { lhs, rhs in
            lhs.isOverdue != rhs.isOverdue ? lhs.isOverdue : lhs.dueDate < rhs.dueDate
        }
    }

    private static let sample = [
        ReminderSnapshot(id: UUID(), title: "Take medicine", dueDate: .now.addingTimeInterval(1800), isOverdue: false,
                         priority: .high, categoryColor: .blue, repeats: true),
        ReminderSnapshot(id: UUID(), title: "Call mom", dueDate: .now.addingTimeInterval(7200), isOverdue: false,
                         priority: .medium, categoryColor: .purple, repeats: false),
        ReminderSnapshot(id: UUID(), title: "Pay rent", dueDate: .now.addingTimeInterval(86400), isOverdue: false,
                         priority: .low, categoryColor: nil, repeats: false),
    ]
}

// MARK: - Views

struct UpcomingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpcomingEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallView(entry: entry)
        case .systemMedium: ListView(entry: entry, limit: 3)
        case .systemLarge: ListView(entry: entry, limit: 7)
        case .accessoryCircular: CircularView(entry: entry)
        case .accessoryRectangular: RectangularView(entry: entry)
        case .accessoryInline: InlineView(entry: entry)
        default: ListView(entry: entry, limit: 3)
        }
    }
}

private struct SmallView: View {
    let entry: UpcomingEntry

    var body: some View {
        if entry.reminders.isEmpty {
            // Centered in the whole widget, with the header pinned on top.
            AllClear()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { Header(count: 0) }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(count: entry.reminders.count)
            Spacer(minLength: 0)
            if let next = entry.reminders.first {
                Text(next.title)
                    .font(.headline)
                    .lineLimit(2)
                DueText(reminder: next)
                    .font(.caption.weight(.semibold))
                if !next.isOverdue {
                    Text(next.dueDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(intent: CompleteReminderIntent(reminderID: next.id.uuidString)) {
                    Label("Done", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(next.priority.color)
            }
        }
    }
}

private struct ListView: View {
    let entry: UpcomingEntry
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(count: entry.reminders.count)
            if entry.reminders.isEmpty {
                Spacer(minLength: 0)
                AllClear().frame(maxWidth: .infinity)
                    .offset(y: -10)  // Balance the header above, so it looks centered in the widget.
                Spacer(minLength: 0)
            } else {
                ForEach(entry.reminders.prefix(limit)) { reminder in
                    Row(reminder: reminder)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct Row: View {
    let reminder: ReminderSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: CompleteReminderIntent(reminderID: reminder.id.uuidString)) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(reminder.title)")

            Circle()
                .fill(reminder.priority.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    DueText(reminder: reminder)
                    if reminder.repeats {
                        Image(systemName: "repeat")
                    }
                }
                .font(.caption2)
            }

            Spacer(minLength: 4)

            if let color = reminder.categoryColor {
                Circle().fill(color).frame(width: 6, height: 6)
            }
        }
    }
}

private struct Header: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.black, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text("Remder")
                .font(.caption.weight(.bold))
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DueText: View {
    let reminder: ReminderSnapshot

    var body: some View {
        Group {
            if reminder.isOverdue {
                Text("Overdue")
                    .foregroundStyle(.red)
            } else if Calendar.current.isDateInToday(reminder.dueDate) {
                Text(reminder.dueDate, format: .dateTime.hour().minute())
                    .foregroundStyle(.secondary)
            } else if Calendar.current.isDateInTomorrow(reminder.dueDate) {
                Text("Tomorrow \(reminder.dueDate, format: .dateTime.hour().minute())")
                    .foregroundStyle(.secondary)
            } else {
                Text(reminder.dueDate, format: .dateTime.weekday(.abbreviated).day().hour().minute())
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }
}

private struct AllClear: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text("All clear")
                .font(.subheadline.weight(.semibold))
            Text("Nothing coming up")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
}

// MARK: Lock Screen

private struct CircularView: View {
    let entry: UpcomingEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "bell.fill")
                    .font(.caption)
                Text("\(entry.dueTodayCount)")
                    .font(.title3.bold())
                    .minimumScaleFactor(0.6)
            }
        }
        .widgetAccentable()
        .accessibilityLabel("\(entry.dueTodayCount) reminders due today")
    }
}

private struct RectangularView: View {
    let entry: UpcomingEntry

    var body: some View {
        if let next = entry.reminders.first {
            VStack(alignment: .leading, spacing: 1) {
                Label("Remder", systemImage: "bell.fill")
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(next.title)
                    .font(.headline)
                    .lineLimit(1)
                DueText(reminder: next)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label("All clear", systemImage: "checkmark.circle")
                .font(.headline)
        }
    }
}

private struct InlineView: View {
    let entry: UpcomingEntry

    var body: some View {
        if let next = entry.reminders.first {
            Label {
                Text("\(next.title) · \(next.dueDate, format: .dateTime.hour().minute())")
            } icon: {
                Image(systemName: "bell.fill")
            }
        } else {
            Label("No reminders", systemImage: "bell")
        }
    }
}
