import Foundation

/// User preferences, stored in UserDefaults. Views bind to these keys with `@AppStorage`;
/// services read them through the static accessors.
enum AppSettings {
    enum Key {
        static let sound = "notificationSound"
        static let snoozeMinutes = "snoozeMinutes"
        static let defaultPriority = "defaultPriority"
        static let defaultLeadMinutes = "defaultLiveActivityLeadMinutes"
        static let defaultAlarm = "defaultAlarmEnabled"
        static let defaultNagMinutes = "defaultNagIntervalMinutes"
        static let useAppleIntelligence = "useAppleIntelligence"
        static let morningBriefEnabled = "morningBriefEnabled"
        static let morningBriefMinutes = "morningBriefMinutes"
        static let eveningCheckInEnabled = "eveningCheckInEnabled"
        static let eveningCheckInMinutes = "eveningCheckInMinutes"
        static let savedPlaces = "savedPlaces"
    }

    static let snoozeOptions = [5, 10, 15, 30, 60]

    private static var defaults: UserDefaults { .standard }

    static var sound: ReminderSound {
        defaults.string(forKey: Key.sound).flatMap(ReminderSound.init(rawValue:)) ?? .standard
    }

    static var snoozeMinutes: Int {
        let value = defaults.integer(forKey: Key.snoozeMinutes)
        return value > 0 ? value : 10
    }

    static var defaultPriority: Priority {
        defaults.object(forKey: Key.defaultPriority) == nil
            ? .medium
            : Priority(rawValue: defaults.integer(forKey: Key.defaultPriority)) ?? .medium
    }

    static var defaultLeadMinutes: Int {
        defaults.integer(forKey: Key.defaultLeadMinutes)
    }

    static var defaultAlarm: Bool {
        defaults.bool(forKey: Key.defaultAlarm)
    }

    static var defaultNagMinutes: Int {
        defaults.integer(forKey: Key.defaultNagMinutes)
    }

    /// Let Apple Intelligence read quick add text (only where it's available). On by default.
    static var useAppleIntelligence: Bool {
        defaults.object(forKey: Key.useAppleIntelligence) == nil ? true : defaults.bool(forKey: Key.useAppleIntelligence)
    }

    // MARK: Daily brief

    /// Morning summary; on by default.
    static var morningBriefEnabled: Bool {
        defaults.object(forKey: Key.morningBriefEnabled) == nil ? true : defaults.bool(forKey: Key.morningBriefEnabled)
    }

    /// Minutes after midnight (8:00 AM by default).
    static var morningBriefMinutes: Int {
        defaults.object(forKey: Key.morningBriefMinutes) == nil ? 8 * 60 : defaults.integer(forKey: Key.morningBriefMinutes)
    }

    static var eveningCheckInEnabled: Bool {
        defaults.bool(forKey: Key.eveningCheckInEnabled)
    }

    /// Minutes after midnight (8:00 PM by default).
    static var eveningCheckInMinutes: Int {
        defaults.object(forKey: Key.eveningCheckInMinutes) == nil ? 20 * 60 : defaults.integer(forKey: Key.eveningCheckInMinutes)
    }

    // MARK: Places

    /// Places saved in Settings, used by location reminders and quick add ("when I get home").
    enum Place: String, CaseIterable, Identifiable {
        case home = "Home"
        case work = "Work"

        var id: String { rawValue }
        var systemImage: String { self == .home ? "house.fill" : "briefcase.fill" }
    }

    static func place(_ place: Place) -> ReminderLocation? {
        savedPlaces[place.rawValue]
    }

    static func setPlace(_ place: Place, to location: ReminderLocation?) {
        var places = savedPlaces
        places[place.rawValue] = location
        defaults.set(try? JSONEncoder().encode(places), forKey: Key.savedPlaces)
    }

    private static var savedPlaces: [String: ReminderLocation] {
        guard let data = defaults.data(forKey: Key.savedPlaces) else { return [:] }
        return (try? JSONDecoder().decode([String: ReminderLocation].self, from: data)) ?? [:]
    }

    /// Choices for nag mode ("Keep reminding every …"); 0 = off.
    static let nagOptions = [0, 5, 10, 15, 30]

    static func nagLabel(_ minutes: Int) -> String {
        minutes == 0 ? "Off" : "Every \(minutes) min"
    }
}

/// Notification sounds. Custom ones ship as .wav files in Remder/Sounds.
enum ReminderSound: String, CaseIterable, Identifiable {
    case standard = "default"
    case chime = "Chime"
    case bell = "Bell"
    case gentle = "Gentle"
    case pulse = "Pulse"
    case alert = "Alert"
    case silent = "none"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Default"
        case .silent: return "None"
        default: return rawValue
        }
    }

    /// Bundled file name, or nil for the system default / silence.
    var fileName: String? {
        switch self {
        case .standard, .silent: return nil
        default: return rawValue + ".wav"
        }
    }
}
