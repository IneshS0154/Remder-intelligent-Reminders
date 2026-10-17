import SwiftUI

extension Priority {
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}
