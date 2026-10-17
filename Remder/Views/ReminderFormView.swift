import SwiftUI
import SwiftData

struct ReminderFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\ReminderCategory.sortOrder), SortDescriptor(\ReminderCategory.createdDate)])
    private var categories: [ReminderCategory]

    let reminder: Reminder?

    @State private var title: String
    @State private var notes: String
    @State private var dueDate: Date
    @State private var priority: Priority
    @State private var category: String
    @State private var repeatRule: RepeatRule?
    @State private var editingRepeat = false
    @State private var remindAt: RemindAt
    @State private var location: ReminderLocation?
    @State private var choosingLocation = false
    @State private var liveActivityLeadMinutes: Int
    @State private var notificationEnabled: Bool
    @State private var alarmEnabled: Bool
    @State private var alarmDenied = false
    @State private var nagIntervalMinutes: Int
    @State private var creatingCategory = false
    @State private var selectedNote: Note?
    @State private var creatingNote = false
    @Query(sort: \Note.updatedDate, order: .reverse) private var allNotes: [Note]

    static let leadTimeOptions = [0, 5, 10, 15, 30, 60]

    enum RemindAt: String, CaseIterable {
        case time, place
    }

    /// `defaultCategory` pre-selects a category for new reminders (e.g. the one being viewed).
    /// `prefill` carries values from quick add when opening the full form for a new reminder.
    init(reminder: Reminder?, defaultCategory: String? = nil, prefill: ParsedReminder? = nil) {
        self.reminder = reminder
        _title = State(initialValue: reminder?.title ?? "")
        _notes = State(initialValue: reminder?.notes ?? "")
        _selectedNote = State(initialValue: reminder?.note)
        _dueDate = State(initialValue: reminder?.dueDate ?? Date().addingTimeInterval(3600))
        _priority = State(initialValue: reminder?.priority ?? AppSettings.defaultPriority)
        _category = State(initialValue: reminder?.category ?? defaultCategory ?? "")
        _repeatRule = State(initialValue: reminder?.repeatRule)
        _location = State(initialValue: reminder?.location)
        _remindAt = State(initialValue: reminder?.isLocationBased == true ? .place : .time)
        _liveActivityLeadMinutes = State(initialValue: reminder?.liveActivityLeadMinutes ?? AppSettings.defaultLeadMinutes)
        _notificationEnabled = State(initialValue: reminder?.notificationEnabled ?? true)
        _alarmEnabled = State(initialValue: reminder?.alarmEnabled ?? AppSettings.defaultAlarm)
        _nagIntervalMinutes = State(initialValue: reminder?.nagIntervalMinutes ?? AppSettings.defaultNagMinutes)

        if reminder == nil, let prefill {
            _title = State(initialValue: prefill.title)
            _dueDate = State(initialValue: prefill.dueDate)
            _repeatRule = State(initialValue: prefill.effectiveRepeatRule)
            if let location = prefill.location {
                _location = State(initialValue: location)
                _remindAt = State(initialValue: .place)
            }
            if let priority = prefill.priority { _priority = State(initialValue: priority) }
            if let category = prefill.category { _category = State(initialValue: category) }
            if prefill.alarm { _alarmEnabled = State(initialValue: true) }
            if let lead = prefill.leadMinutes { _liveActivityLeadMinutes = State(initialValue: lead) }
        }
    }

    private var hasAnyAlert: Bool {
        remindAt == .place ? notificationEnabled : (notificationEnabled || alarmEnabled || liveActivityLeadMinutes > 0)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasAnyAlert
            && (remindAt == .time || location != nil)
    }

    /// A custom repeat starts on its first matching day; show that date rather than the picked one.
    private var effectiveDueDate: Date {
        guard let repeatRule, RepeatChoice(repeatRule) == .custom else { return dueDate }
        return repeatRule.firstOccurrence(onOrAfter: dueDate) ?? dueDate
    }

    /// Picker choices: managed categories, plus the reminder's current one if it was deleted meanwhile.
    private var categoryNames: [String] {
        let names = categories.map(\.name)
        return category.isEmpty || names.contains(category) ? names : names + [category]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }

                Section("Details") {
                    TextField("Add a short description", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Picker("Note", selection: $selectedNote) {
                        Text("None").tag(Note?.none)
                        ForEach(allNotes) { note in
                            Text(note.displayTitle).tag(Optional(note))
                        }
                    }
                    if let selectedNote, !selectedNote.preview.isEmpty {
                        Text(selectedNote.preview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    Button("New Note…", systemImage: "square.and.pencil") { creatingNote = true }
                } header: {
                    Text("Note")
                } footer: {
                    Text("Attach a note from the Notes section for the full details. It's shown when the reminder goes off.")
                }

                Section {
                    Picker("Remind me", selection: $remindAt.animation(.snappy)) {
                        Label("At a Time", systemImage: "clock").tag(RemindAt.time)
                        Label("At a Place", systemImage: "location").tag(RemindAt.place)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if remindAt == .time {
                    Section {
                        DatePicker("Date & Time", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                        Picker("Repeat", selection: Binding(
                            get: { RepeatChoice(repeatRule) },
                            set: { choice in
                                if choice == .custom {
                                    editingRepeat = true
                                } else {
                                    repeatRule = choice.rule
                                }
                            }
                        )) {
                            ForEach(RepeatChoice.allCases) { choice in
                                Text(choice == .custom && RepeatChoice(repeatRule) == .custom ? "Custom" : choice.label).tag(choice)
                            }
                        }
                        if let repeatRule, RepeatChoice(repeatRule) == .custom {
                            Button {
                                editingRepeat = true
                            } label: {
                                LabeledContent {
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                                } label: {
                                    Label(repeatRule.summary, systemImage: "repeat")
                                }
                            }
                            .tint(.primary)
                        }
                    } header: {
                        Text("Due")
                    } footer: {
                        // Spell out the day: late at night the default (an hour from now) is already tomorrow.
                        TimelineView(.everyMinute) { _ in
                            Text(Self.dueSummary(effectiveDueDate))
                                .foregroundStyle(effectiveDueDate <= .now && repeatRule == nil ? .red : .secondary)
                        }
                    }
                } else {
                    Section {
                        Button {
                            choosingLocation = true
                        } label: {
                            LabeledContent {
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            } label: {
                                if let location {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(location.summary)
                                            Text(location.repeats ? "Every time" : "Once")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: "location.fill").foregroundStyle(.teal)
                                    }
                                } else {
                                    Label("Choose a Place", systemImage: "mappin.and.ellipse")
                                }
                            }
                        }
                        .tint(.primary)
                    } header: {
                        Text("Place")
                    } footer: {
                        if LocationPermission.isDenied {
                            Text("Location is off for Remder. Turn it on in Settings › Remder › Location, or this reminder can't go off.")
                                .foregroundStyle(.red)
                        } else {
                            Text("Your iPhone lets you know when you arrive or leave. Remder never tracks where you go.")
                        }
                    }
                }

                Section {
                    Toggle(isOn: $notificationEnabled) {
                        Label("Notification", systemImage: "bell.badge")
                    }
                    if remindAt == .time {
                    Toggle(isOn: Binding(get: { alarmEnabled }, set: setAlarm)) {
                        Label("Alarm", systemImage: "alarm")
                    }
                    }
                    if remindAt == .time, notificationEnabled || alarmEnabled {
                        Picker(selection: $nagIntervalMinutes) {
                            ForEach(AppSettings.nagOptions, id: \.self) { minutes in
                                Text(AppSettings.nagLabel(minutes)).tag(minutes)
                            }
                        } label: {
                            Label("Keep reminding", systemImage: "arrow.trianglehead.2.clockwise")
                        }
                    }
                    if remindAt == .time {
                        Picker(selection: $liveActivityLeadMinutes) {
                            ForEach(Self.leadTimeOptions, id: \.self) { minutes in
                                Text(Self.leadTimeLabel(minutes)).tag(minutes)
                            }
                        } label: {
                            Label("Dynamic Island", systemImage: "timer")
                        }
                    }
                } header: {
                    Text("Remind Me With")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if !hasAnyAlert {
                            Text("Choose at least one way to be reminded.")
                                .foregroundStyle(.red)
                        }
                        if remindAt == .place {
                            Text("Alarms and the countdown need a time, so they're off for place reminders.")
                        } else if alarmDenied {
                            Text("Alarms are turned off for Remder. Allow them in Settings › Remder › Alarms.")
                                .foregroundStyle(.red)
                        } else if alarmEnabled {
                            Text("The alarm rings full screen \(Self.dayAndTime(effectiveDueDate)), even in Silent mode or a Focus, with Snooze.")
                        }
                        if remindAt == .time, nagIntervalMinutes > 0 && (notificationEnabled || alarmEnabled) {
                            Text("If it's not done, you'll get a follow-up notification every \(nagIntervalMinutes) min after it's due, up to \(NotificationManager.maxNags) times.")
                        }
                        if remindAt == .time, liveActivityLeadMinutes > 0 {
                            if LiveActivityManager.shared.areActivitiesEnabled {
                                let start = effectiveDueDate.addingTimeInterval(-TimeInterval(liveActivityLeadMinutes * 60))
                                Text("A live countdown appears in the Dynamic Island and on the Lock Screen \(Self.dayAndTime(start)) and stays until you mark the reminder done.")
                            } else {
                                Text("Live Activities are turned off for Remder. Turn them on in Settings › Remder › Live Activities, or the countdown won't appear.")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        Text("None").tag("")
                        ForEach(categoryNames, id: \.self) { name in
                            Label {
                                Text(name)
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(categories.first { $0.name == name }?.color.color ?? .gray)
                            }
                            .tag(name)
                        }
                    }
                    Button("New Category…", systemImage: "plus") { creatingCategory = true }
                }
            }
            .navigationTitle(reminder == nil ? "New Reminder" : "Edit Reminder")
            .sheet(isPresented: $creatingNote) {
                NewNoteSheet { selectedNote = $0 }
            }
            .sheet(isPresented: $creatingCategory) {
                CategoryEditorView(category: nil) { category = $0 }
            }
            .sheet(isPresented: $editingRepeat) {
                RepeatRuleEditor(rule: repeatRule, dueDate: dueDate) { repeatRule = $0 }
            }
            .sheet(isPresented: $choosingLocation) {
                LocationPickerView(title: "Place", current: location) { location = $0 }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCategory = category
        // A category typed in quick add that doesn't exist yet is created now.
        if !finalCategory.isEmpty, !categories.contains(where: { $0.name == finalCategory }) {
            let order = (categories.map(\.sortOrder).max() ?? -1) + 1
            modelContext.insert(ReminderCategory(name: finalCategory, color: CategoryStore.nextColor(avoiding: categories), sortOrder: order))
        }

        let target: Reminder
        if let reminder {
            target = reminder
            target.title = title
            target.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            target.dueDate = dueDate
            target.priority = priority
            target.category = finalCategory
            target.liveActivityLeadMinutes = liveActivityLeadMinutes
            target.note = selectedNote
            target.notificationEnabled = notificationEnabled
            target.alarmEnabled = alarmEnabled
            target.nagIntervalMinutes = nagIntervalMinutes
        } else {
            target = Reminder(
                title: title,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                dueDate: dueDate,
                priority: priority,
                category: finalCategory,
                liveActivityLeadMinutes: liveActivityLeadMinutes
            )
            modelContext.insert(target)
            target.note = selectedNote
            target.notificationEnabled = notificationEnabled
            target.alarmEnabled = alarmEnabled
            target.nagIntervalMinutes = nagIntervalMinutes
        }

        if remindAt == .place, let location {
            // Goes off at the place; time-only options don't apply.
            target.location = location
            target.repeatRule = nil
            target.alarmEnabled = false
            target.liveActivityLeadMinutes = 0
            target.nagIntervalMinutes = 0
        } else {
            target.location = nil
            target.repeatRule = repeatRule
            target.snapToRepeatRule()
        }

        try? modelContext.save()
        NotificationManager.shared.reschedule(for: target)
        dismiss()
    }

    /// e.g. "Today at 11:14 PM · in 7 min", "Tomorrow at 11:14 PM · in 1 day".
    static func dueSummary(_ date: Date) -> String {
        guard date > .now else { return "\(dayAndTime(date).capitalizedFirst) · already passed" }
        let relative = date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        return "\(dayAndTime(date).capitalizedFirst) · \(relative)"
    }

    /// "today at 11:14 PM", "tomorrow at 9:00 AM", or "on Fri, 26 Sep at 9:00 AM".
    static func dayAndTime(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today at \(time)" }
        if calendar.isDateInTomorrow(date) { return "tomorrow at \(time)" }
        if calendar.isDateInYesterday(date) { return "yesterday at \(time)" }
        return "on \(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) at \(time)"
    }

    /// Turning the alarm on asks for alarm permission the first time.
    private func setAlarm(_ enabled: Bool) {
        guard enabled else {
            alarmEnabled = false
            return
        }
        alarmEnabled = true
        Task {
            let allowed = await AlarmScheduler.shared.requestAuthorization()
            alarmDenied = !allowed
            if !allowed { alarmEnabled = false }
        }
    }

    static func leadTimeLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Off"
        case 60: return "1 hour"
        default: return "\(minutes) min"
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
