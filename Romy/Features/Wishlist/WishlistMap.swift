import MapKit
import SwiftUI

/// The map above 「行きたい」 (Notion 02 §6-6, 2026-10-14): a ♥ pin for each saved place, in the color of the day it
/// was added to, grey while it is not in the itinerary. Like the itinerary's map it sits behind the sheet.
struct WishlistMap: View {
    let trip: Trip

    @State private var position: MapCameraPosition = .rect(ItineraryPins.rect(of: PlaceSearch.japan))
    @State private var destinationPoints: [CLLocationCoordinate2D] = []

    /// Changes when the map should frame its pins again.
    private var frameKey: [String] { trip.wishes.map(\.id.uuidString) + [String(destinationPoints.count)] }

    var body: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let aspect = geometry.size.width / (geometry.size.height + insets.top + insets.bottom)
            // Read here, not inside the map's content, so a pin changes color when its place is added to a day.
            let pins = trip.wishes.map { (wish: $0, color: color(of: $0)) }
            Map(position: $position) {
                UserAnnotation()
                ForEach(pins, id: \.wish.id) { pin in
                    Annotation("", coordinate: pin.wish.location.coordinate, anchor: .center) {
                        heart(pin.wish.title, color: pin.color)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()
            .task(id: trip.destinations.map(\.id)) {
                destinationPoints = await PlaceSearch.coordinates(of: trip.destinations)
            }
            .onChange(of: frameKey, initial: true) { _, _ in frame(aspect: aspect) }
        }
    }

    /// The color of the day the place was added to; grey while it is not in the itinerary.
    private func color(of wish: WishPlace) -> Color {
        trip.plan(for: wish).map { Theme.dayColor($0.day) } ?? Theme.secondary
    }

    private func heart(_ title: String, color: Color) -> some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(color))
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            .accessibilityLabel("\(title)、行きたい")
    }

    /// Pins first; with none, the trip's destinations; with no destination either, all of Japan.
    private func frame(aspect: Double) {
        let points = trip.wishes.map(\.location.coordinate)
        let target = ItineraryPins.rect(around: points)
            ?? PlaceSearch.region(around: destinationPoints).map(ItineraryPins.rect(of:))
            ?? ItineraryPins.rect(of: PlaceSearch.japan)
        let rect = ItineraryPins.rect(showing: target, visibleFraction: 0.3, aspect: aspect)
        withAnimation(.easeInOut(duration: 0.4)) { position = .rect(rect) }
    }
}
