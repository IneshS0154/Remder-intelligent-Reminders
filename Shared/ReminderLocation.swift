import CoreLocation
import Foundation

/// Where a location reminder goes off. iOS watches the area itself (a notification with a
/// region trigger), so Remder never tracks where you are.
nonisolated struct ReminderLocation: Codable, Hashable, Sendable {
    enum Trigger: String, Codable, CaseIterable, Sendable {
        case arriving, leaving

        var label: String { self == .arriving ? "Arriving" : "Leaving" }
    }

    var name: String
    var latitude: Double
    var longitude: Double
    /// Meters around the place. iOS works best with at least ~100 m.
    var radius: Double = 150
    var trigger: Trigger = .arriving
    /// Go off every time (e.g. each time you get home) instead of once.
    var repeats: Bool = false

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// "Arriving at Home", "Leaving Work".
    var summary: String {
        trigger == .arriving ? "Arriving at \(name)" : "Leaving \(name)"
    }

    var region: CLCircularRegion {
        let region = CLCircularRegion(center: coordinate, radius: radius, identifier: "\(latitude),\(longitude)")
        region.notifyOnEntry = trigger == .arriving
        region.notifyOnExit = trigger == .leaving
        return region
    }

    static let radiusOptions: [Double] = [100, 150, 300, 500, 1000]
}
