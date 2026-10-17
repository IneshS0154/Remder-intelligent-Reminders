import Foundation
import SwiftData

/// A standalone note that can be attached to one or more reminders for extra detail.
@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var createdDate: Date = Date.now
    var updatedDate: Date = Date.now

    /// Reminders this note is attached to. Deleting the note just detaches it.
    @Relationship(deleteRule: .nullify, inverse: \Reminder.note)
    var reminders: [Reminder] = []

    init(title: String = "", body: String = "") {
        self.title = title
        self.body = body
    }

    /// The title, or the body's first line when the title is empty.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return firstLine.isEmpty ? "New Note" : firstLine
    }

    /// Body text for previews, without the line already used as the title.
    var preview: String {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? body.split(whereSeparator: \.isNewline).dropFirst().joined(separator: " ")
            : body.split(whereSeparator: \.isNewline).joined(separator: " ")
        return text.trimmingCharacters(in: .whitespaces)
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
