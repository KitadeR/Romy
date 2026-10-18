import MapKit
import SwiftUI

/// The move between two plans (Notion 02 §6-5 ②移動の行). First version: the 経路 button to Apple Maps,
/// from the plan before to this one; travel time and choosing Google Maps come later (Notion 05).
/// 未定 has no order of visits, so it has no moves; plans without a place have no route.
struct RouteRow: View {
    let origin: ItineraryItem
    let destination: ItineraryItem
    let isOnADay: Bool
    /// The time line passing through this move; it continues the line of the plan before (nil in 未定).
    let line: TimeLineStyle?

    var body: some View {
        Group {
            if isOnADay, let start = RouteLink.mapItem(origin), let end = RouteLink.mapItem(destination) {
                HStack {
                    Spacer()
                    Button { RouteLink.open(from: start, to: end) } label: {
                        Text("経路")
                            .font(Theme.jp(12, .bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Capsule().fill(Theme.fill))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(origin.title)から\(destination.title)への経路")
                }
                .padding(.vertical, 2)
            } else {
                Color.clear.frame(height: 4)
            }
        }
        .background { if isOnADay, let line { TimeLine(style: line) } }
    }
}

/// Opens the route between two plans in Apple Maps (Notion 02 §6-5; Google Maps comes later).
enum RouteLink {
    static func mapItem(_ item: ItineraryItem) -> MKMapItem? {
        guard let latitude = item.latitude, let longitude = item.longitude else { return nil }
        let mapItem = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        mapItem.name = item.title
        return mapItem
    }

    static func open(from origin: MKMapItem, to destination: MKMapItem) {
        MKMapItem.openMaps(
            with: [origin, destination],
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault]
        )
    }
}
