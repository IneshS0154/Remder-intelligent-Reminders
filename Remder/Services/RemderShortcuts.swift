import AppIntents
import CoreLocation
import Foundation
import MapKit
import GeoToolbox
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// Siri and Shortcuts.
//
// Classic Siri (every iPhone): "Add a reminder in Remder" → "What should I remind you about?"
// → "Call mom tomorrow at 5" (and "When?" if no time was said). Also "What's next in Remder"
// and "Mark <reminder> as done in Remder".
//
// Siri with Apple Intelligence: `CreateReminderIntent` adopts Apple's Reminders schema, so one
// sentence is enough: "Remind me in Remder to call mom tomorrow at 5".

// MARK: - Classic Siri: add a reminder

struct AddReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Reminder"
    static let description = IntentDescription("Adds a reminder from a line of text, like “Call mom tomorrow at 5pm”.")

    @Parameter(title: "Reminder", requestValueDialog: "What should I remind you about?")
    var text: String

    @Parameter(title: "When", requestValueDialog: "When should I remind you?")
    var when: Date?

    @Parameter(title: "List")
    var list: ReminderListEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to Remder") {
            \.$when
            \.$list
        }
    }

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<ReminderEntity> & ShowsSnippetView {
        try AccountError.requireSignIn()
        let context = RemderApp.sharedContainer.mainContext
        let categories = (try? context.fetch(FetchDescriptor<ReminderCategory>())) ?? []
        var parsed = await QuickAdd.interpret(text, categories: categories.map(\.name))
        guard !parsed.title.isEmpty else {
            throw $text.needsValueError("What should I remind you about?")
        }

        if let when {
            parsed.dueDate = when
        } else if !parsed.hasExplicitDate, parsed.location == nil {
            // "Add a reminder in Remder" → "Call mom" → Siri asks when, then runs this again.
            throw $when.needsValueError("When should I remind you?")
        }
        if let list, !list.id.isEmpty { parsed.category = list.id }

        await NotificationManager.shared.requestAuthorizationIfNeeded()
        let reminder = QuickAdd.save(parsed, categories: categories, in: context)
        let entity = ReminderEntity(reminder)
        return .result(
            value: entity,
            dialog: IntentDialog(
                full: "OK, I'll remind you to \(Self.spoken(reminder.title)) \(Self.spokenWhen(reminder)).",
                supporting: "Added to Remder."
            ),
            view: ReminderSnippetView(entity: entity)
        )
    }

    /// "tomorrow at 5:00 PM", or "when you get to Home".
    static func spokenWhen(_ reminder: Reminder) -> String {
        guard let location = reminder.location else { return ReminderFormView.dayAndTime(reminder.dueDate) }
        return location.trigger == .arriving ? "when you get to \(location.name)" : "when you leave \(location.name)"
    }

    /// "Call mom" → "call mom", to read naturally after "remind you to".
    static func spoken(_ title: String) -> String {
        guard let first = title.first, title.dropFirst().first?.isLowercase ?? true else { return title }
        return first.lowercased() + title.dropFirst()
    }
}

// MARK: - Siri with Apple Intelligence: create a reminder

/// Apple's Reminders schema. Siri fills the fields from one natural sentence; Remder maps them
/// onto its own reminder. Locations, sections and images aren't supported and are ignored.
@AppIntent(schema: .reminders.createReminder)
struct CreateReminderIntent: AppIntent {
    var title: String
    var dueDate: DateComponents?
    var images: [IntentFile]
    var isFlagged: Bool?
    var list: ReminderListEntity?
    var locationTrigger: ReminderLocationEntity?
    var note: String?
    var recurrence: Calendar.RecurrenceRule?
    var section: ReminderSectionEntity?
    var tags: Set<String>
    var urls: [URL]

    @MainActor
    func perform() async throws -> some ReturnsValue<ReminderEntity> & ProvidesDialog {
        try AccountError.requireSignIn()
        let context = RemderApp.sharedContainer.mainContext
        let categories = (try? context.fetch(FetchDescriptor<ReminderCategory>())) ?? []
        let names = categories.map(\.name)

        // Start from the offline parser, in case Siri left words like "every day" in the title.
        var parsed = QuickAddParser.parse(title, categories: names)
        if parsed.title.isEmpty { parsed.title = title }
        if let dueDate, let date = Self.date(from: dueDate) {
            parsed.dueDate = date
        }
        if let rule = recurrence {
            parsed.repeatRule = rule
        }
        if let locationTrigger, let location = await locationTrigger.reminderLocation() {
            parsed.location = location
        }
        if isFlagged == true { parsed.priority = .high }
        if let list, !list.id.isEmpty {
            parsed.category = list.id
        } else if let tag = tags.lazy.compactMap({ tag in names.first { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame } }).first {
            parsed.category = tag
        }

        await NotificationManager.shared.requestAuthorizationIfNeeded()
        let reminder = QuickAdd.save(parsed, categories: categories, in: context)
        let details = ([note] + urls.map(\.absoluteString)).compactMap { $0 }.filter { !$0.isEmpty }
        if !details.isEmpty {
            reminder.notes = details.joined(separator: "\n")
            try? context.save()
        }
        return .result(
            value: ReminderEntity(reminder),
            dialog: "OK, I'll remind you to \(AddReminderIntent.spoken(reminder.title)) \(AddReminderIntent.spokenWhen(reminder))."
        )
    }

    /// Siri may send only some parts ("tomorrow" or "5 PM"); fill in the rest sensibly.
    static func date(from components: DateComponents, now: Date = .now) -> Date? {
        let calendar = Calendar.current
        var parts = components
        parts.calendar = calendar
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        let hasDay = components.day != nil || components.weekday != nil
        let hasTime = components.hour != nil
        if components.day == nil, let weekday = components.weekday {
            // "Friday at 5": the next Friday (today only if that time is still ahead).
            var match = DateComponents(hour: components.hour ?? 9, minute: components.minute ?? 0, weekday: weekday)
            match.calendar = calendar
            return calendar.nextDate(after: now, matching: match, matchingPolicy: .nextTime)
        }
        if parts.year == nil { parts.year = today.year }
        if parts.month == nil { parts.month = today.month }
        if parts.day == nil { parts.day = today.day }
        if !hasTime {
            parts.hour = 9
            parts.minute = 0
        }
        guard var date = calendar.date(from: parts) else { return nil }
        if !hasDay, hasTime, date <= now {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date  // "at 5" after 5 → tomorrow
        }
        return date
    }
}

// MARK: - Upcoming and done

struct UpcomingRemindersIntent: AppIntent {
    static let title: LocalizedStringResource = "Upcoming Reminders"
    static let description = IntentDescription("Tells you your next reminders.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<[ReminderEntity]> {
        try AccountError.requireSignIn()
        let upcoming = ReminderQuery.activeReminders()
        guard !upcoming.isEmpty else {
            return .result(value: [], dialog: "You're all clear. Nothing is coming up.")
        }
        let spoken = upcoming.prefix(3)
            .map { "\($0.title) \(ReminderFormView.dayAndTime($0.nextDue))" }
            .joined(separator: ", then ")
        let more = upcoming.count > 3 ? " You have \(upcoming.count - 3) more after that." : ""
        return .result(value: upcoming, dialog: "Next up: \(spoken).\(more)")
    }
}

struct MarkReminderDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Reminder Done"
    static let description = IntentDescription("Completes a reminder. Repeating reminders move on to their next time.")

    @Parameter(title: "Reminder")
    var reminder: ReminderEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$reminder) as done")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try AccountError.requireSignIn()
        let found = ReminderIntentHandler.perform(on: reminder.id) { NotificationManager.shared.complete($0) }
        return .result(dialog: found ? "Done! “\(reminder.title)” is complete." : "I couldn't find that reminder.")
    }
}

struct RemderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddReminderIntent(),
            phrases: [
                "Add a reminder in \(.applicationName)",
                "Add a \(.applicationName) reminder",
                "New \(.applicationName) reminder",
                "Create a reminder in \(.applicationName)",
                "Set a reminder in \(.applicationName)",
                "Remind me with \(.applicationName)",
                "Add a reminder to \(\.$list) in \(.applicationName)",
                "Add a \(\.$list) reminder in \(.applicationName)",
            ],
            shortTitle: "Add Reminder",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: UpcomingRemindersIntent(),
            phrases: [
                "What's next in \(.applicationName)",
                "Show my \(.applicationName) reminders",
                "What are my \(.applicationName) reminders",
            ],
            shortTitle: "Upcoming",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: MarkReminderDoneIntent(),
            phrases: [
                "Mark \(\.$reminder) as done in \(.applicationName)",
                "Complete \(\.$reminder) in \(.applicationName)",
                "Complete a \(.applicationName) reminder",
            ],
            shortTitle: "Mark Done",
            systemImageName: "checkmark.circle.fill"
        )
    }
}

// MARK: - Snippet

/// The card Siri shows after adding a reminder.
struct ReminderSnippetView: View {
    let entity: ReminderEntity

    static func dueText(_ date: Date) -> String {
        let text = ReminderFormView.dayAndTime(date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(entity.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(Self.dueText(entity.nextDue))
                    if entity.recurrence != nil {
                        Image(systemName: "repeat")
                    }
                    if !entity.list.id.isEmpty {
                        Text("· \(entity.list.name)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if entity.isFlagged == true {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
    }
}

// MARK: - Entities

@AppEntity(schema: .reminders.reminder)
struct ReminderEntity: AppEntity {
    static let defaultQuery = ReminderQuery()

    var id: UUID
    var title: String
    var note: String?
    var dueDate: DateComponents?
    var creationDate: Date?
    var completionDate: Date?
    var isCompleted: Bool
    /// High priority.
    var isFlagged: Bool?
    /// The reminder's category ("Reminders" when it has none).
    var list: ReminderListEntity
    var locationTrigger: ReminderLocationEntity?
    var recurrence: Calendar.RecurrenceRule?
    var tags: Set<String>
    var urls: [URL]

    /// When it's next due, for sorting and speaking.
    let nextDue: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(nextDue.formatted(date: .abbreviated, time: .shortened))",
            image: .init(systemName: isCompleted ? "checkmark.circle.fill" : "bell")
        )
    }

    @MainActor
    init(_ reminder: Reminder) {
        let due = reminder.upcomingDueDate
        nextDue = due
        id = reminder.id
        title = reminder.title
        note = reminder.notes ?? reminder.note?.body
        dueDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        creationDate = reminder.createdDate
        completionDate = reminder.completedDate
        isCompleted = reminder.isCompleted
        isFlagged = reminder.priority == .high
        list = ReminderListEntity(category: reminder.category)
        locationTrigger = reminder.location.map(ReminderLocationEntity.init)
        recurrence = reminder.repeatRule
        tags = []
        urls = []
    }
}

nonisolated struct ReminderQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ReminderEntity] {
        await MainActor.run {
            let context = RemderApp.sharedContainer.mainContext
            let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
            return reminders.filter { identifiers.contains($0.id) }.map(ReminderEntity.init)
        }
    }

    func entities(matching string: String) async throws -> [ReminderEntity] {
        await MainActor.run {
            Self.activeReminders().filter { $0.title.localizedCaseInsensitiveContains(string) }
        }
    }

    func suggestedEntities() async throws -> [ReminderEntity] {
        await MainActor.run { Self.activeReminders() }
    }

    /// Active reminders, soonest first.
    @MainActor
    static func activeReminders() -> [ReminderEntity] {
        let context = RemderApp.sharedContainer.mainContext
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>(predicate: #Predicate { !$0.isCompleted }))) ?? []
        return reminders.map(ReminderEntity.init).sorted { $0.nextDue < $1.nextDue }
    }
}

/// A Remder category, presented to Siri as a reminders list. The id is the category name;
/// an empty id means "no category".
@AppEntity(schema: .reminders.list)
struct ReminderListEntity: AppEntity {
    static let defaultQuery = ReminderListQuery()

    var id: String
    var name: String
    var type: ReminderListType

    init(category: String) {
        id = category
        name = category.isEmpty ? "Reminders" : category
        type = .standard
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: id.isEmpty ? "tray" : "number"))
    }
}

nonisolated struct ReminderListQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ReminderListEntity] {
        await MainActor.run { Self.all().filter { identifiers.contains($0.id) } }
    }

    func entities(matching string: String) async throws -> [ReminderListEntity] {
        await MainActor.run { Self.all().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    }

    func suggestedEntities() async throws -> [ReminderListEntity] {
        await MainActor.run { Self.all() }
    }

    @MainActor
    private static func all() -> [ReminderListEntity] {
        let context = RemderApp.sharedContainer.mainContext
        let descriptor = FetchDescriptor<ReminderCategory>(sortBy: [SortDescriptor(\.sortOrder)])
        let categories = (try? context.fetch(descriptor)) ?? []
        return categories.map { ReminderListEntity(category: $0.name) }
    }
}

@AppEnum(schema: .reminders.listType)
enum ReminderListType: String, AppEnum {
    case standard
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.standard: "List"]
}

/// Required by Apple's Reminders schema; Remder has no sections, so these are never stored.
@AppEntity(schema: .reminders.section)
struct ReminderSectionEntity: TransientAppEntity {
    var name: String
    var list: ReminderListEntity

    init() {
        name = ""
        list = ReminderListEntity(category: "")
    }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

/// "When I get home": the place and whether it's on arriving or leaving.
@AppEntity(schema: .reminders.locationTrigger)
struct ReminderLocationEntity: TransientAppEntity {
    var event: ReminderLocationEvent
    var place: PlaceDescriptor

    init() {
        event = .arrive
        place = PlaceDescriptor(representations: [.address("")], commonName: nil)
    }

    init(_ location: ReminderLocation) {
        event = location.trigger == .arriving ? .arrive : .depart
        place = PlaceDescriptor(representations: [.coordinate(location.coordinate)], commonName: location.name)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(event == .arrive ? "Arriving at" : "Leaving") \(place.commonName ?? "a place")")
    }

    /// Coordinates straight from Siri, a saved place ("home", "work"), or the address looked up.
    func reminderLocation() async -> ReminderLocation? {
        let trigger: ReminderLocation.Trigger = event == .arrive ? .arriving : .leaving
        let name = place.commonName ?? "a place"
        for representation in place.representations {
            if case .coordinate(let coordinate) = representation {
                return ReminderLocation(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude, trigger: trigger)
            }
        }
        if let saved = await MainActor.run(body: { AppSettings.Place.allCases.first { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame } }),
           var location = await MainActor.run(body: { AppSettings.place(saved) }) {
            location.trigger = trigger
            return location
        }
        for representation in place.representations {
            if case .address(let address) = representation, !address.isEmpty,
               let request = MKGeocodingRequest(addressString: address),
               let item = try? await request.mapItems.first {
                let coordinate = item.location.coordinate
                return ReminderLocation(name: place.commonName ?? item.name ?? address,
                                        latitude: coordinate.latitude, longitude: coordinate.longitude, trigger: trigger)
            }
        }
        return nil
    }
}

@AppEnum(schema: .reminders.locationTriggerEvent)
enum ReminderLocationEvent: String, AppEnum {
    case arrive, depart
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.arrive: "Arrive", .depart: "Leave"]
}
