import CoreLocation
import MapKit
import SwiftUI

/// Assigns a nearby place to an expense. Places come from Apple Maps points of interest,
/// which replace the retired Foursquare v2 API (and its client secret).
struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var venue: Venue?

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var places: [Venue] = []
    @State private var selectedID: String?
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var location = LocationPermission()

    var body: some View {
        Map(position: $position, selection: $selectedID) {
            UserAnnotation()
            ForEach(places) { place in
                Marker(place.name, systemImage: "mappin",
                       coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))
                    .tag(place.id)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        .task(id: RegionKey(visibleRegion)) {
            guard let visibleRegion else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await searchPlaces(in: visibleRegion)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(.tint)
                Text(selectedPlace?.name ?? String(localized: "Tap a place on the map"))
                    .lineLimit(2)
                Spacer()
                if selectedID != nil {
                    Button("Remove", systemImage: "xmark.circle.fill") { selectedID = nil }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
        }
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    venue = selectedPlace
                    dismiss()
                }
            }
        }
        .onAppear {
            if let venue {
                selectedID = venue.id
                places = [venue]
                let center = CLLocationCoordinate2D(latitude: venue.latitude, longitude: venue.longitude)
                position = .region(MKCoordinateRegion(center: center, latitudinalMeters: 400, longitudinalMeters: 400))
            } else {
                location.requestIfNeeded()
            }
        }
    }

    private var selectedPlace: Venue? {
        places.first { $0.id == selectedID }
    }

    private func searchPlaces(in region: MKCoordinateRegion) async {
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        guard let response = try? await MKLocalSearch(request: request).start() else { return }
        var found = response.mapItems.compactMap(Venue.init(mapItem:))
        // Keep the selected place even when it is outside the new results.
        if let selected = selectedPlace, !found.contains(where: { $0.id == selected.id }) {
            found.append(selected)
        }
        places = found
    }
}

/// Lets `.task(id:)` restart when the visible region changes.
private struct RegionKey: Equatable {
    let values: [Double]

    init(_ region: MKCoordinateRegion?) {
        guard let region else { values = []; return }
        values = [region.center.latitude, region.center.longitude, region.span.latitudeDelta, region.span.longitudeDelta]
    }
}

extension Venue {
    init?(mapItem: MKMapItem) {
        guard let name = mapItem.name else { return nil }
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26.0, *) {
            coordinate = mapItem.location.coordinate
        } else {
            coordinate = mapItem.placemark.coordinate
        }
        let id: String
        if #available(iOS 18.0, *), let identifier = mapItem.identifier {
            id = identifier.rawValue
        } else {
            id = "apple:\(name)@\(coordinate.latitude),\(coordinate.longitude)"
        }
        self.init(id: id, name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

/// Asks for "when in use" location access the first time the map is opened.
@MainActor
@Observable
final class LocationPermission {
    @ObservationIgnored private let manager = CLLocationManager()

    func requestIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
}
