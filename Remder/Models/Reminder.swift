import Foundation
import SwiftData

enum Priority: Int, Codable, CaseIterable, Identifiable {
    case low = 0
    case medium = 1
    case high = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

enum RepeatFrequency: Int, Codable, CaseIterable, Identifiable {
    case none = 0
    case daily = 1
    case weekly = 2
    case monthly = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return "Never"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

@Model
final class Reminder {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String?
    var dueDate: Date
    var priority: Priority
    var category: String
    var isCompleted: Bool
    var completedDate: Date?
    var repeatFrequency: RepeatFrequency
    var createdDate: Date

    init(
        title: String,
        notes: String? = nil,
        dueDate: Date,
        priority: Priority = .medium,
        category: String = "General",
        repeatFrequency: RepeatFrequency = .none
    ) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
        self.category = category
        self.isCompleted = false
        self.completedDate = nil
        self.repeatFrequency = repeatFrequency
        self.createdDate = .now
    }
}
