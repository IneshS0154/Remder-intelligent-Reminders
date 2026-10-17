import Foundation
import SwiftData
import SwiftUI

/// A user-managed category. Reminders refer to it by name (`Reminder.category`);
/// an empty name on a reminder means "no category".
@Model
final class ReminderCategory {
    var name: String
    var colorName: String
    var sortOrder: Int
    var createdDate: Date

    init(name: String, color: CategoryColor = .blue, sortOrder: Int = 0) {
        self.name = name
        self.colorName = color.rawValue
        self.sortOrder = sortOrder
        self.createdDate = .now
    }

    var color: CategoryColor {
        get { CategoryColor(rawValue: colorName) ?? .blue }
        set { colorName = newValue.rawValue }
    }
}

enum CategoryColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        case .gray: return .gray
        }
    }
}

enum CategoryStore {
    private static let seededKey = "didSeedCategories"

    /// One-time setup: turn category names already used by reminders into managed categories.
    static func seedIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        let reminders = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        let existing = Set(((try? context.fetch(FetchDescriptor<ReminderCategory>())) ?? []).map(\.name))
        let names = Set(reminders.map(\.category).filter { !$0.isEmpty }).subtracting(existing).sorted()
        let palette = CategoryColor.allCases
        for (index, name) in names.enumerated() {
            context.insert(ReminderCategory(name: name, color: palette[(index + 6) % palette.count], sortOrder: existing.count + index))
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// A color not used by any existing category yet (cycling when all are taken).
    static func nextColor(avoiding existing: [ReminderCategory]) -> CategoryColor {
        let used = Set(existing.map(\.colorName))
        let preferred: [CategoryColor] = [.blue, .purple, .green, .orange, .pink, .teal, .red, .indigo, .yellow, .mint, .brown, .gray]
        return preferred.first { !used.contains($0.rawValue) } ?? preferred[existing.count % preferred.count]
    }

    /// Renames a category and moves its reminders along with it.
    static func rename(_ category: ReminderCategory, to newName: String, in context: ModelContext) {
        let oldName = category.name
        guard oldName != newName else { return }
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.category == oldName })
        for reminder in (try? context.fetch(descriptor)) ?? [] {
            reminder.category = newName
        }
        category.name = newName
        try? context.save()
    }

    /// Deletes a category; its reminders are kept and become uncategorised.
    static func delete(_ category: ReminderCategory, in context: ModelContext) {
        let name = category.name
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.category == name })
        for reminder in (try? context.fetch(descriptor)) ?? [] {
            reminder.category = ""
        }
        context.delete(category)
        try? context.save()
    }
}
