import SwiftUI

/// The choices in the form's Repeat menu. Anything the presets don't cover is "Custom".
enum RepeatChoice: String, CaseIterable, Identifiable {
    case never, daily, weekdays, weekly, everyTwoWeeks, monthly, yearly, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: return "Never"
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .everyTwoWeeks: return "Every 2 Weeks"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .custom: return "Custom…"
        }
    }

    /// The rule for a preset choice (nil for Never and Custom).
    var rule: RepeatRule? {
        switch self {
        case .never, .custom: return nil
        case .daily: return .daily(calendar: .current)
        case .weekdays: return .weekdays()
        case .weekly: return .weekly(calendar: .current)
        case .everyTwoWeeks: return .everyTwoWeeks()
        case .monthly: return .monthly(calendar: .current)
        case .yearly: return .yearly(calendar: .current)
        }
    }

    init(_ rule: RepeatRule?) {
        guard let rule else {
            self = .never
            return
        }
        self = Self.allCases.first { choice in
            guard let preset = choice.rule else { return false }
            return PortableRepeatRule(preset) == PortableRepeatRule(rule)
        } ?? .custom
    }
}

/// Custom repeat, like Apple's Reminders: every N days/weeks/months/years, on chosen weekdays,
/// on a day of the month or "the last Friday", with an optional end date.
struct RepeatRuleEditor: View {
    @Environment(\.dismiss) private var dismiss

    let dueDate: Date
    let onSave: (RepeatRule) -> Void

    enum Frequency: String, CaseIterable, Identifiable {
        case daily, weekly, monthly, yearly
        var id: String { rawValue }
        var label: String { rawValue.capitalized }

        func unit(_ count: Int) -> String {
            let single = ["daily": "day", "weekly": "week", "monthly": "month", "yearly": "year"][rawValue] ?? "day"
            return count == 1 ? single : single + "s"
        }
    }

    enum MonthlyMode: String, CaseIterable, Identifiable {
        case day, weekday
        var id: String { rawValue }
    }

    @State private var frequency: Frequency
    @State private var interval: Int
    @State private var weekdays: Set<Locale.Weekday>
    @State private var monthlyMode: MonthlyMode
    @State private var dayOfMonth: Int
    @State private var position: Int
    @State private var positionWeekday: Locale.Weekday
    @State private var hasEnd: Bool
    @State private var endDate: Date

    private static let positions = [1, 2, 3, 4, -1]

    init(rule: RepeatRule?, dueDate: Date, onSave: @escaping (RepeatRule) -> Void) {
        self.dueDate = dueDate
        self.onSave = onSave
        let calendar = Calendar.current
        let dueWeekday = Locale.Weekday(date: dueDate)
        let day = calendar.component(.day, from: dueDate)

        let frequency: Frequency = switch rule?.frequency {
        case .weekly?: .weekly
        case .monthly?: .monthly
        case .yearly?: .yearly
        default: rule == nil ? .weekly : .daily
        }
        _frequency = State(initialValue: frequency)
        _interval = State(initialValue: rule?.interval ?? 1)
        let chosen = Set(rule?.everyWeekdays ?? [])
        _weekdays = State(initialValue: chosen.isEmpty ? [dueWeekday] : chosen)

        if case .nth(let n, let weekday)? = rule?.weekdays.first {
            _monthlyMode = State(initialValue: .weekday)
            _position = State(initialValue: n)
            _positionWeekday = State(initialValue: weekday)
        } else {
            _monthlyMode = State(initialValue: .day)
            // Which week of the month the due date falls in, for "On the …".
            let week = (day - 1) / 7 + 1
            _position = State(initialValue: day + 7 > (calendar.range(of: .day, in: .month, for: dueDate)?.count ?? 31) ? -1 : min(week, 4))
            _positionWeekday = State(initialValue: dueWeekday)
        }
        _dayOfMonth = State(initialValue: rule?.daysOfTheMonth.first ?? day)
        _hasEnd = State(initialValue: rule?.endDate != nil)
        _endDate = State(initialValue: rule?.endDate ?? calendar.date(byAdding: .month, value: 3, to: dueDate) ?? dueDate)
    }

    /// The rule as currently set up.
    private var rule: RepeatRule {
        let calendar = Calendar.current
        let end: RepeatRule.End = hasEnd ? .afterDate(calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate) : .never
        switch frequency {
        case .daily:
            return RepeatRule(calendar: calendar, frequency: .daily, interval: interval, end: end)
        case .weekly:
            return RepeatRule(calendar: calendar, frequency: .weekly, interval: interval, end: end,
                              weekdays: orderedWeekdays.filter(weekdays.contains).map { .every($0) })
        case .monthly:
            return monthlyMode == .day
                ? RepeatRule(calendar: calendar, frequency: .monthly, interval: interval, end: end, daysOfTheMonth: [dayOfMonth])
                : RepeatRule(calendar: calendar, frequency: .monthly, interval: interval, end: end, weekdays: [.nth(position, positionWeekday)])
        case .yearly:
            return RepeatRule(calendar: calendar, frequency: .yearly, interval: interval, end: end)
        }
    }

    /// The week in the user's order (Monday first in most places).
    private var orderedWeekdays: [Locale.Weekday] {
        let first = Calendar.current.firstWeekday - 1
        return Array(Locale.Weekday.ordered[first...] + Locale.Weekday.ordered[..<first])
    }

    /// The next few times it will go off, starting from the reminder's date.
    private var preview: [Date] {
        Array(rule.recurrences(of: dueDate).prefix(4))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(Frequency.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper(value: $interval, in: 1...99) {
                        LabeledContent("Every", value: "\(interval) \(frequency.unit(interval))")
                    }
                }

                if frequency == .weekly {
                    Section("On") {
                        HStack(spacing: 6) {
                            ForEach(orderedWeekdays, id: \.self) { day in
                                weekdayChip(day)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    }
                }

                if frequency == .monthly {
                    Section {
                        Picker("Repeat on", selection: $monthlyMode) {
                            Text("Day of Month").tag(MonthlyMode.day)
                            Text("Day of Week").tag(MonthlyMode.weekday)
                        }
                        .pickerStyle(.segmented)

                        if monthlyMode == .day {
                            Picker("On the", selection: $dayOfMonth) {
                                ForEach(1...31, id: \.self) { Text(RepeatRule.ordinal($0)).tag($0) }
                            }
                        } else {
                            Picker("On the", selection: $position) {
                                ForEach(Self.positions, id: \.self) { Text(RepeatRule.ordinalWord($0)).tag($0) }
                            }
                            Picker("Day", selection: $positionWeekday) {
                                ForEach(orderedWeekdays, id: \.self) { Text($0.fullName).tag($0) }
                            }
                        }
                    } footer: {
                        if monthlyMode == .day, dayOfMonth > 28 {
                            Text("Months without a \(RepeatRule.ordinal(dayOfMonth)) are skipped.")
                        }
                    }
                }

                Section {
                    Toggle("End Repeat", isOn: $hasEnd.animation())
                    if hasEnd {
                        DatePicker("On", selection: $endDate, in: dueDate..., displayedComponents: .date)
                    }
                }

                Section {
                    Text(rule.summary)
                        .font(.headline)
                    ForEach(preview, id: \.self) { date in
                        Text(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).hour().minute()))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Next Times")
                } footer: {
                    if preview.isEmpty {
                        Text("This repeat never goes off. Check the end date.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Custom Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(rule)
                        dismiss()
                    }
                    .disabled(preview.isEmpty || (frequency == .weekly && weekdays.isEmpty))
                }
            }
        }
    }

    private func weekdayChip(_ day: Locale.Weekday) -> some View {
        let isOn = weekdays.contains(day)
        return Button {
            if isOn, weekdays.count > 1 { weekdays.remove(day) } else { weekdays.insert(day) }
        } label: {
            Text(day.initial)
                .font(.subheadline.weight(.semibold))
                .frame(width: 38, height: 38)
                .foregroundStyle(isOn ? .white : .primary)
                .background(isOn ? Color.accentColor : Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.fullName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
