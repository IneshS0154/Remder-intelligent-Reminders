import CoreLocation
import MapKit
import Observation
import SwiftUI

/// Pick where a location reminder goes off: search for a place, use where you are now, or a
/// saved place (Home, Work). Shows the area on a map with an adjustable radius.
struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    /// Hide Arriving/Leaving and "Every time" when picking a saved place in Settings.
    var choosesTrigger = true
    let onPick: (ReminderLocation) -> Void

    @State private var selection: ReminderLocation?
    @State private var search = PlaceSearch()
    @State private var locator = CurrentLocation()
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var camera: MapCameraPosition = .automatic

    init(title: String = "Location", current: ReminderLocation? = nil, choosesTrigger: Bool = true,
         onPick: @escaping (ReminderLocation) -> Void) {
        self.title = title
        self.choosesTrigger = choosesTrigger
        self.onPick = onPick
        _selection = State(initialValue: current)
    }

    var body: some View {
        NavigationStack {
            List {
                if let selection {
                    Section {
                        map(for: selection)
                            .frame(height: 190)
                            .listRowInsets(EdgeInsets())

                        LabeledContent("Place", value: selection.name)
                        Picker("Radius", selection: Binding(
                            get: { selection.radius },
                            set: { self.selection?.radius = $0 }
                        )) {
                            ForEach(ReminderLocation.radiusOptions, id: \.self) { meters in
                                Text(meters >= 1000 ? "\(Int(meters / 1000)) km" : "\(Int(meters)) m").tag(meters)
                            }
                        }
                        if choosesTrigger {
                            Picker("Remind me when", selection: Binding(
                                get: { selection.trigger },
                                set: { self.selection?.trigger = $0 }
                            )) {
                                ForEach(ReminderLocation.Trigger.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Toggle("Every time", isOn: Binding(
                                get: { selection.repeats },
                                set: { self.selection?.repeats = $0 }
                            ))
                        }
                    } footer: {
                        if choosesTrigger {
                            Text(selection.repeats
                                 ? "Goes off every time you \(selection.trigger == .arriving ? "arrive at" : "leave") \(selection.name)."
                                 : "Goes off the next time you \(selection.trigger == .arriving ? "arrive at" : "leave") \(selection.name).")
                        }
                    }
                }

                Section {
                    Button {
                        useCurrentLocation()
                    } label: {
                        Label("Current Location", systemImage: "location.fill")
                    }
                    ForEach(AppSettings.Place.allCases) { place in
                        if let saved = AppSettings.place(place), choosesTrigger {
                            Button {
                                choose(ReminderLocation(name: place.rawValue, latitude: saved.latitude, longitude: saved.longitude,
                                                        radius: saved.radius, trigger: selection?.trigger ?? .arriving))
                            } label: {
                                Label(place.rawValue, systemImage: place.systemImage)
                            }
                        }
                    }
                } footer: {
                    if choosesTrigger, AppSettings.Place.allCases.allSatisfy({ AppSettings.place($0) == nil }) {
                        Text("Save Home and Work in Settings › Places to pick them here, or to say “when I get home” in quick add.")
                    }
                }

                if !search.results.isEmpty {
                    Section("Results") {
                        ForEach(search.results, id: \.self) { result in
                            Button {
                                resolve(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title).foregroundStyle(.primary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a place or address")
            .overlay {
                if isResolving { ProgressView() }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let selection { onPick(selection) }
                        dismiss()
                    }
                    .disabled(selection == nil)
                }
            }
            .alert("Couldn't Get Location", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task { LocationPermission.requestIfNeeded() }
        }
    }

    private func map(for location: ReminderLocation) -> some View {
        Map(position: $camera) {
            MapCircle(center: location.coordinate, radius: location.radius)
                .foregroundStyle(.teal.opacity(0.2))
                .stroke(.teal, lineWidth: 2)
            Marker(location.name, systemImage: "mappin", coordinate: location.coordinate)
                .tint(.teal)
        }
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        .onAppear { frame(location) }
        .onChange(of: location) { _, new in frame(new) }
    }

    private func frame(_ location: ReminderLocation) {
        let span = max(location.radius * 5, 600)
        withAnimation {
            camera = .region(MKCoordinateRegion(center: location.coordinate, latitudinalMeters: span, longitudinalMeters: span))
        }
    }

    private func choose(_ location: ReminderLocation) {
        var location = location
        if let current = selection {
            location.trigger = current.trigger
            location.repeats = current.repeats
        }
        withAnimation { selection = location }
        search.query = ""
    }

    private func resolve(_ completion: MKLocalSearchCompletion) {
        isResolving = true
        Task {
            defer { isResolving = false }
            let request = MKLocalSearch.Request(completion: completion)
            guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
                errorMessage = "That place couldn't be found. Try another search."
                return
            }
            let coordinate = item.location.coordinate
            choose(ReminderLocation(name: item.name ?? completion.title, latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
    }

    private func useCurrentLocation() {
        isResolving = true
        Task {
            defer { isResolving = false }
            guard let location = await locator.fetch() else {
                errorMessage = "Allow location access for Remder in Settings to use your current location."
                return
            }
            var name = "Current Location"
            if let request = MKReverseGeocodingRequest(location: location),
               let item = try? await request.mapItems.first, let itemName = item.name {
                name = itemName
            }
            choose(ReminderLocation(name: name, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
        }
    }
}

// MARK: - Helpers

/// Location reminders need "While Using the App" permission for iOS to watch the area.
enum LocationPermission {
    private static let manager = CLLocationManager()

    static func requestIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    static var isDenied: Bool {
        [.denied, .restricted].contains(manager.authorizationStatus)
    }
}

/// Where the phone is right now (one reading).
@Observable
final class CurrentLocation {
    func fetch() async -> CLLocation? {
        LocationPermission.requestIfNeeded()
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location { return location }
                if update.authorizationDenied || update.authorizationDeniedGlobally { return nil }
            }
        } catch {
            return nil
        }
        return nil
    }
}

/// Place suggestions as you type, from MapKit.
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    var query = "" {
        didSet {
            if query.isEmpty {
                results = []
            } else {
                completer.queryFragment = query
            }
        }
    }

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            results = query.isEmpty ? [] : Array(completer.results.prefix(8))
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}
