import MapKit
import SwiftUI

/// A numbered pin: the plan's number in its day, in the day's color (Notion 02 §6-5 「地図の決まり」).
struct MapPin: Identifiable, Equatable {
    let id: UUID
    let number: Int
    let day: Int
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// Which pins the map shows (Notion 02 §6-5): a day tab shows that day, 全体 every day,
/// and plans in 未定 or without a place are not on the map.
enum ItineraryPins {
    static func days(for tab: ItineraryTab, dayCount: Int) -> [Int] {
        switch tab {
        case .all: dayCount > 0 ? Array(1...dayCount) : []
        case .day(let number): [number]
        case .undecided: []
        }
    }

    /// Numbers count every plan of the day, so a pin keeps the same number as its card
    /// even when a plan before it has no place.
    static func pins(day: Int, items: [ItineraryItem]) -> [MapPin] {
        items.enumerated().compactMap { index, item in
            guard let latitude = item.latitude, let longitude = item.longitude else { return nil }
            return MapPin(id: item.id, number: index + 1, day: day, latitude: latitude, longitude: longitude)
        }
    }

    /// The area that holds all the points, with room around them. One point gets a street-level area.
    nonisolated static func rect(around points: [CLLocationCoordinate2D]) -> MKMapRect? {
        guard !points.isEmpty else { return nil }
        let rects = points.map { MKMapRect(origin: MKMapPoint($0), size: MKMapSize(width: 0, height: 0)) }
        let union = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        let minimum = MKMapPointsPerMeterAtLatitude(points[0].latitude) * 1500
        let width = max(union.width * 1.4, minimum)
        let height = max(union.height * 1.4, minimum)
        return MKMapRect(x: union.midX - width / 2, y: union.midY - height / 2, width: width, height: height)
    }

    /// The area to show so that `target` sits in the middle of the top part of the map that the sheet
    /// leaves open. `visibleFraction` is that part's share of the map's height, `aspect` the map's width/height.
    nonisolated static func rect(showing target: MKMapRect, visibleFraction: Double, aspect: Double) -> MKMapRect {
        let fraction = min(max(visibleFraction, 0.1), 1)
        let width = max(target.width, target.height / fraction * aspect)
        let height = width / aspect
        let openHeight = height * fraction
        return MKMapRect(
            x: target.midX - width / 2,
            y: target.midY - openHeight / 2,
            width: width,
            height: height
        )
    }

    nonisolated static func rect(of region: MKCoordinateRegion) -> MKMapRect {
        let corners = [
            CLLocationCoordinate2D(
                latitude: region.center.latitude + region.span.latitudeDelta / 2,
                longitude: region.center.longitude - region.span.longitudeDelta / 2
            ),
            CLLocationCoordinate2D(
                latitude: region.center.latitude - region.span.latitudeDelta / 2,
                longitude: region.center.longitude + region.span.longitudeDelta / 2
            )
        ].map(MKMapPoint.init)
        return MKMapRect(
            x: min(corners[0].x, corners[1].x), y: min(corners[0].y, corners[1].y),
            width: abs(corners[1].x - corners[0].x), height: abs(corners[1].y - corners[0].y)
        )
    }
}

/// The map above the itinerary (Notion 02 §6-5, Figma 124:2). First version: numbered round pins in the
/// day's color joined by straight lines (the three pin sizes and lines along roads come later, Notion 05).
/// The map moves by itself only when the trip opens, the tab changes, a plan is added, or a pin is tapped —
/// never because the sheet is pulled.
struct ItineraryMap: View {
    let trip: Trip
    let selection: ItineraryTab
    /// Share of the map's height left open above the sheet at its middle height, and the map's width/height,
    /// so the pins are framed in the part that shows.
    let visibleFraction: Double
    let aspect: Double
    let onAddDestination: () -> Void

    @State private var position: MapCameraPosition = .rect(ItineraryPins.rect(of: PlaceSearch.japan))
    @State private var destinationPoints: [CLLocationCoordinate2D] = []

    private var groups: [(day: Int, pins: [MapPin])] {
        ItineraryPins.days(for: selection, dayCount: ItineraryDays.count(of: trip.dates)).map { day in
            (day, ItineraryPins.pins(day: day, items: trip.items(on: day)))
        }
    }

    private var pins: [MapPin] { groups.flatMap(\.pins) }

    /// Changes when the map should frame its pins again.
    private var frameKey: [String] {
        [String(describing: selection)] + pins.map(\.id.uuidString) + [String(destinationPoints.count)]
    }

    var body: some View {
        Map(position: $position) {
            ForEach(groups, id: \.day) { group in
                if group.pins.count > 1 {
                    MapPolyline(coordinates: group.pins.map(\.coordinate))
                        .stroke(
                            Theme.dayColor(group.day),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                }
            }
            ForEach(pins) { pin in
                Annotation("", coordinate: pin.coordinate, anchor: .center) {
                    Button { focus(on: pin) } label: { pinLabel(pin) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(pin.day)日目の\(pin.number)番目")
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .overlay(alignment: .top) {
            if trip.destinations.isEmpty {
                // In the middle of the open map when it is empty (Figma 16-6); near the top once
                // there are pins, so it never sits on top of one.
                GeometryReader { geometry in
                    addDestinationButton
                        .position(
                            x: geometry.size.width / 2,
                            y: pins.isEmpty ? geometry.size.height * visibleFraction / 2 : 90
                        )
                }
            }
        }
        .task(id: trip.destinations.map(\.id)) {
            destinationPoints = await PlaceSearch.coordinates(of: trip.destinations)
        }
        .onChange(of: frameKey, initial: true) { _, _ in frame() }
    }

    private func pinLabel(_ pin: MapPin) -> some View {
        Text("\(pin.number)")
            .font(Theme.latin(12, .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Theme.dayColor(pin.day)))
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }

    /// Figma 16-6: a trip without a destination shows one button on the map.
    private var addDestinationButton: some View {
        Button(action: onAddDestination) {
            Label("行き先を追加", systemImage: "plus")
                .font(Theme.jp(14, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Capsule().fill(Theme.surface))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    /// Pins first; with none, the trip's destinations; with no destination either, all of Japan (Notion 02 §6-6).
    private func frame() {
        let target = ItineraryPins.rect(around: pins.map(\.coordinate))
            ?? PlaceSearch.region(around: destinationPoints).map(ItineraryPins.rect(of:))
            ?? ItineraryPins.rect(of: PlaceSearch.japan)
        show(target)
    }

    private func focus(on pin: MapPin) {
        if let rect = ItineraryPins.rect(around: [pin.coordinate]) { show(rect) }
    }

    private func show(_ target: MKMapRect) {
        let rect = ItineraryPins.rect(showing: target, visibleFraction: visibleFraction, aspect: aspect)
        withAnimation(.easeInOut(duration: 0.4)) { position = .rect(rect) }
    }
}
