import CryptoKit
import Foundation
import Observation
import Supabase
import SwiftData

/// Two-way sync between this iPhone's SwiftData store and the `sync_records` table.
///
/// Every reminder, note, category and completion is one row, keyed by kind + key.
/// Each sync:
/// 1. **Pull:** fetch rows the server changed since the last pull and apply them. The server's
///    copy wins, so an edit on another device replaces this one.
/// 2. **Push:** compare the local data with what was last synced (a hash per record). New or
///    changed records are uploaded; records that disappeared are uploaded as deleted.
///
/// It runs after sign-in, whenever the app comes forward, and a moment after local saves.
@MainActor
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    enum Status: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastSyncedAt: Date?

    private var userID: UUID?
    private var state = SyncState()
    private var isSyncing = false
    private var needsAnotherSync = false
    private var isApplyingRemote = false
    private var debounce: Task<Void, Never>?
    private var saveObserver: NSObjectProtocol?

    private var context: ModelContext { RemderApp.sharedContainer.mainContext }

    private init() {}

    // MARK: - Lifecycle

    func start(userID: UUID) {
        self.userID = userID
        state = SyncState.load(for: userID)
        lastSyncedAt = state.lastSyncedAt
        if saveObserver == nil {
            saveObserver = NotificationCenter.default.addObserver(
                forName: ModelContext.didSave, object: nil, queue: nil
            ) { _ in
                // Delivered on the saving thread; the app's own saves happen on the main thread,
                // which is what lets `isApplyingRemote` filter out saves made by the sync itself.
                if Thread.isMainThread {
                    MainActor.assumeIsolated { SyncEngine.shared.localDataChanged() }
                } else {
                    Task { @MainActor in SyncEngine.shared.localDataChanged() }
                }
            }
        }
        Task { await syncNow() }
    }

    func stop() {
        userID = nil
        debounce?.cancel()
        status = .idle
    }

    /// Local saves trigger a sync shortly after, batching quick edits like typing a note.
    private func localDataChanged() {
        guard userID != nil, !isApplyingRemote else { return }
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    func syncNow() async {
        guard let userID else { return }
        guard !isSyncing else {
            needsAnotherSync = true
            return
        }
        isSyncing = true
        status = .syncing
        defer { isSyncing = false }

        do {
            try await pull(userID: userID)
            try await push(userID: userID)
            state.lastSyncedAt = .now
            lastSyncedAt = state.lastSyncedAt
            state.save(for: userID)
            status = .idle
        } catch {
            status = .failed(AccountError.message(for: error))
        }

        if needsAnotherSync {
            needsAnotherSync = false
            await syncNow()
        }
    }

    /// Removes everything from this iPhone after signing out, so the next account starts clean.
    /// Their data stays in the cloud.
    func clearLocalData() async {
        // Forget what was synced too. Otherwise signing back in would read the now-empty store
        // as "everything was deleted" and remove it from the cloud.
        SyncState.deleteAll()
        stop()
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        for reminder in reminders { NotificationManager.shared.cancel(for: reminder) }
        try? context.delete(model: Completion.self)
        try? context.delete(model: Reminder.self)
        try? context.delete(model: Note.self)
        try? context.delete(model: ReminderCategory.self)
        try? context.save()
        await NotificationManager.shared.resync(reminders: [])
    }

    // MARK: - Pull

    private func pull(userID: UUID) async throws {
        // Start a little before the last cursor so rows committed out of order aren't missed.
        // No cursor yet (first sync on this iPhone): fetch everything.
        let since = state.cursor?.addingTimeInterval(-10)
        var rows: [RemoteRow] = []
        let pageSize = 1000
        while true {
            var query = supabase.from("sync_records")
                .select("kind, key, data, deleted, updated_at")
                .eq("user_id", value: userID.uuidString)
            if let since {
                query = query.gt("updated_at", value: since.ISO8601Format())
            }
            let page: [RemoteRow] = try await query
                .order("updated_at")
                .range(from: rows.count, to: rows.count + pageSize - 1)
                .execute()
                .value
            rows += page
            if page.count < pageSize { break }
        }
        guard !rows.isEmpty else { return }

        isApplyingRemote = true
        defer { isApplyingRemote = false }

        var changedAnything = false
        // Parents first, so reminders can find their note and completions their reminder.
        let order = [RecordKind.category, .note, .reminder, .completion]
        for kind in order {
            for row in rows where row.kind == kind.rawValue {
                let id = RecordID(kind: kind, key: row.key)
                if row.deleted {
                    if state.hashes[id.path] != nil || localObjectExists(id) {
                        deleteLocal(id)
                        changedAnything = true
                    }
                    state.hashes[id.path] = nil
                } else if let data = row.data, let json = try? JSONEncoder().encode(data) {
                    let hash = Self.hash(json)
                    guard state.hashes[id.path] != hash || !localObjectExists(id) else { continue }
                    apply(id, json: json)
                    state.hashes[id.path] = hash
                    changedAnything = true
                }
            }
        }
        if let newest = rows.compactMap({ Self.parseTimestamp($0.updatedAt) }).max() {
            state.cursor = max(newest, state.cursor ?? newest)
        }

        guard changedAnything else { return }
        try? context.save()
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        await NotificationManager.shared.resync(reminders: reminders)
    }

    // MARK: - Push

    private func push(userID: UUID) async throws {
        let records = localRecords()
        var upserts: [PushRow] = []
        var newHashes: [String: String] = [:]

        for (path, record) in records {
            let hash = Self.hash(record.json)
            newHashes[path] = hash
            guard state.hashes[path] != hash else { continue }
            upserts.append(PushRow(
                userID: userID, kind: record.id.kind.rawValue, key: record.id.key,
                data: try JSONDecoder().decode(AnyJSON.self, from: record.json), deleted: false
            ))
        }
        for path in state.hashes.keys where records[path] == nil {
            guard let id = RecordID(path: path) else { continue }
            upserts.append(PushRow(userID: userID, kind: id.kind.rawValue, key: id.key, data: nil, deleted: true))
        }
        guard !upserts.isEmpty else { return }

        for batch in stride(from: 0, to: upserts.count, by: 500).map({ Array(upserts[$0..<min($0 + 500, upserts.count)]) }) {
            try await supabase.from("sync_records")
                .upsert(batch, onConflict: "user_id,kind,key")
                .execute()
        }
        state.hashes = newHashes
    }

    // MARK: - Local records

    private struct LocalRecord {
        let id: RecordID
        let json: Data
    }

    private func localRecords() -> [String: LocalRecord] {
        var records: [String: LocalRecord] = [:]
        func add<T: Encodable>(_ kind: RecordKind, _ key: String, _ value: T) {
            guard let json = try? Self.encoder.encode(value) else { return }
            let id = RecordID(kind: kind, key: key)
            records[id.path] = LocalRecord(id: id, json: json)
        }
        for category in (try? context.fetch(FetchDescriptor<ReminderCategory>())) ?? [] {
            add(.category, category.name, CategoryRecord(category))
        }
        for note in (try? context.fetch(FetchDescriptor<Note>())) ?? [] {
            add(.note, note.id.uuidString, NoteRecord(note))
        }
        for reminder in (try? context.fetch(FetchDescriptor<Reminder>())) ?? [] {
            add(.reminder, reminder.id.uuidString, ReminderRecord(reminder))
            for completion in reminder.completions {
                add(.completion, CompletionRecord.key(reminderID: reminder.id, occurrence: completion.occurrenceDate),
                    CompletionRecord(completion, reminderID: reminder.id))
            }
        }
        return records
    }

    private func localObjectExists(_ id: RecordID) -> Bool {
        switch id.kind {
        case .category: return category(named: id.key) != nil
        case .note: return UUID(uuidString: id.key).flatMap(note(id:)) != nil
        case .reminder: return UUID(uuidString: id.key).flatMap(reminder(id:)) != nil
        case .completion: return completion(key: id.key) != nil
        }
    }

    private func deleteLocal(_ id: RecordID) {
        switch id.kind {
        case .category:
            if let category = category(named: id.key) { context.delete(category) }
        case .note:
            if let note = UUID(uuidString: id.key).flatMap(note(id:)) { context.delete(note) }
        case .reminder:
            if let reminder = UUID(uuidString: id.key).flatMap(reminder(id:)) {
                NotificationManager.shared.cancel(for: reminder)
                context.delete(reminder)
            }
        case .completion:
            if let completion = completion(key: id.key) { context.delete(completion) }
        }
    }

    private func apply(_ id: RecordID, json: Data) {
        let decoder = Self.decoder
        switch id.kind {
        case .category:
            guard let record = try? decoder.decode(CategoryRecord.self, from: json) else { return }
            let category = category(named: id.key) ?? {
                let new = ReminderCategory(name: id.key)
                context.insert(new)
                return new
            }()
            record.apply(to: category)
        case .note:
            guard let record = try? decoder.decode(NoteRecord.self, from: json), let uuid = UUID(uuidString: id.key) else { return }
            let note = note(id: uuid) ?? {
                let new = Note()
                new.id = uuid
                context.insert(new)
                return new
            }()
            record.apply(to: note)
        case .reminder:
            guard let record = try? decoder.decode(ReminderRecord.self, from: json), let uuid = UUID(uuidString: id.key) else { return }
            let reminder = reminder(id: uuid) ?? {
                let new = Reminder(title: record.title, dueDate: record.dueDate)
                new.id = uuid
                context.insert(new)
                return new
            }()
            record.apply(to: reminder, note: record.noteID.flatMap(note(id:)))
        case .completion:
            guard let record = try? decoder.decode(CompletionRecord.self, from: json),
                  let parent = reminder(id: record.reminderID) else { return }
            if let existing = completion(key: id.key) {
                existing.completedAt = record.completedAt
            } else {
                let completion = Completion(occurrenceDate: record.occurrenceDate, completedAt: record.completedAt)
                context.insert(completion)
                completion.reminder = parent
            }
        }
    }

    private func category(named name: String) -> ReminderCategory? {
        try? context.fetch(FetchDescriptor<ReminderCategory>(predicate: #Predicate { $0.name == name })).first
    }

    private func note(id: UUID) -> Note? {
        try? context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })).first
    }

    private func reminder(id: UUID) -> Reminder? {
        try? context.fetch(FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == id })).first
    }

    private func completion(key: String) -> Completion? {
        guard let (reminderID, occurrence) = CompletionRecord.parse(key: key),
              let parent = reminder(id: reminderID) else { return nil }
        return parent.completions.first { CompletionRecord.sameOccurrence($0.occurrenceDate, occurrence) }
    }

    // MARK: - Helpers

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    /// Hash of a record's canonical JSON (re-encoded so key order and number formatting match).
    private static func hash(_ json: Data) -> String {
        let canonical = (try? JSONSerialization.jsonObject(with: json))
            .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) } ?? json
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }

    private static func parseTimestamp(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - Rows

private struct RemoteRow: Decodable {
    let kind: String
    let key: String
    let data: AnyJSON?
    let deleted: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case kind, key, data, deleted
        case updatedAt = "updated_at"
    }
}

private struct PushRow: Encodable {
    let userID: UUID
    let kind: String
    let key: String
    let data: AnyJSON?
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case kind, key, data, deleted
        case userID = "user_id"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(kind, forKey: .kind)
        try container.encode(key, forKey: .key)
        try container.encode(data ?? .null, forKey: .data)
        try container.encode(deleted, forKey: .deleted)
    }
}

enum RecordKind: String {
    case category, note, reminder, completion
}

private struct RecordID {
    let kind: RecordKind
    let key: String

    init(kind: RecordKind, key: String) {
        self.kind = kind
        self.key = key
    }

    init?(path: String) {
        guard let slash = path.firstIndex(of: "/"),
              let kind = RecordKind(rawValue: String(path[..<slash])) else { return nil }
        self.kind = kind
        key = String(path[path.index(after: slash)...])
    }

    var path: String { "\(kind.rawValue)/\(key)" }
}

// MARK: - Records

private struct CategoryRecord: Codable {
    var colorName: String
    var sortOrder: Int
    var createdDate: Date

    init(_ category: ReminderCategory) {
        colorName = category.colorName
        sortOrder = category.sortOrder
        createdDate = category.createdDate
    }

    func apply(to category: ReminderCategory) {
        category.colorName = colorName
        category.sortOrder = sortOrder
        category.createdDate = createdDate
    }
}

private struct NoteRecord: Codable {
    var title: String
    var body: String
    var createdDate: Date
    var updatedDate: Date

    init(_ note: Note) {
        title = note.title
        body = note.body
        createdDate = note.createdDate
        updatedDate = note.updatedDate
    }

    func apply(to note: Note) {
        note.title = title
        note.body = body
        note.createdDate = createdDate
        note.updatedDate = updatedDate
    }
}

private struct ReminderRecord: Codable {
    var title: String
    var notes: String?
    var dueDate: Date
    var priority: Int
    var category: String
    var isCompleted: Bool
    var completedDate: Date?
    var repeatFrequency: Int
    var createdDate: Date
    var liveActivityLeadMinutes: Int
    var noteID: UUID?
    var notificationEnabled: Bool
    var alarmEnabled: Bool
    var nagIntervalMinutes: Int
    /// Newer fields are optional, so records from older app versions still decode.
    var repeatRule: PortableRepeatRule?
    var location: ReminderLocation?

    init(_ reminder: Reminder) {
        title = reminder.title
        notes = reminder.notes
        dueDate = reminder.dueDate
        priority = reminder.priority.rawValue
        category = reminder.category
        isCompleted = reminder.isCompleted
        completedDate = reminder.completedDate
        repeatFrequency = reminder.repeatFrequency.rawValue
        createdDate = reminder.createdDate
        liveActivityLeadMinutes = reminder.liveActivityLeadMinutes
        noteID = reminder.note?.id
        notificationEnabled = reminder.notificationEnabled
        alarmEnabled = reminder.alarmEnabled
        nagIntervalMinutes = reminder.nagIntervalMinutes
        repeatRule = reminder.repeatFrequency == .custom ? reminder.repeatRule.map(PortableRepeatRule.init) : nil
        location = reminder.location
    }

    @MainActor
    func apply(to reminder: Reminder, note: Note?) {
        reminder.title = title
        reminder.notes = notes
        reminder.dueDate = dueDate
        reminder.priority = Priority(rawValue: priority) ?? .medium
        reminder.category = category
        reminder.isCompleted = isCompleted
        reminder.completedDate = completedDate
        reminder.repeatFrequency = RepeatFrequency(rawValue: repeatFrequency) ?? .none
        reminder.createdDate = createdDate
        reminder.liveActivityLeadMinutes = liveActivityLeadMinutes
        reminder.note = note
        reminder.notificationEnabled = notificationEnabled
        reminder.alarmEnabled = alarmEnabled
        reminder.nagIntervalMinutes = nagIntervalMinutes
        if let repeatRule {
            reminder.repeatRule = repeatRule.rule
        } else if reminder.repeatFrequency == .custom {
            reminder.repeatRuleData = nil
        }
        reminder.location = location
    }
}

private struct CompletionRecord: Codable {
    var reminderID: UUID
    var occurrenceDate: Date
    var completedAt: Date

    init(_ completion: Completion, reminderID: UUID) {
        self.reminderID = reminderID
        occurrenceDate = completion.occurrenceDate
        completedAt = completion.completedAt
    }

    /// "<reminder id>@<occurrence, whole seconds>"
    static func key(reminderID: UUID, occurrence: Date) -> String {
        "\(reminderID.uuidString)@\(Int(occurrence.timeIntervalSince1970.rounded()))"
    }

    static func parse(key: String) -> (UUID, Date)? {
        let parts = key.split(separator: "@")
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])), let seconds = Double(parts[1]) else { return nil }
        return (id, Date(timeIntervalSince1970: seconds))
    }

    static func sameOccurrence(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince1970 - rhs.timeIntervalSince1970) < 1
    }
}

// MARK: - State

/// What this iPhone last synced for one account: a hash per record and the pull cursor.
private struct SyncState: Codable {
    var cursor: Date?
    var lastSyncedAt: Date?
    var hashes: [String: String] = [:]

    private static func url(for userID: UUID) -> URL {
        let directory = URL.applicationSupportDirectory.appending(path: "Sync", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(userID.uuidString).json")
    }

    static func load(for userID: UUID) -> SyncState {
        guard let data = try? Data(contentsOf: url(for: userID)),
              let state = try? JSONDecoder().decode(SyncState.self, from: data) else { return SyncState() }
        return state
    }

    func save(for userID: UUID) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.url(for: userID), options: .atomic)
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "Sync", directoryHint: .isDirectory))
    }
}
