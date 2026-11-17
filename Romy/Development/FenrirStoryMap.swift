#if DEBUG
import MapKit
import SwiftUI

struct FenrirStoryMap: View {
    let screen: Int
    let selectedA: Bool
    private struct RouteRecord: Decodable {
        let from: String
        let coordinates: [[Double]]
    }

    private var lines: [[CLLocationCoordinate2D]] {
        guard let url = Bundle.main.url(forResource: "fenrir-routes", withExtension: "json"),
              let data = try? Data(contentsOf: url), let routes = try? JSONDecoder().decode(
                  [RouteRecord].self,
                  from: data) else { return [] }
        return routes.prefix(screen == 5 ? 5 : selectedA ? 3 : 5).enumerated().compactMap { index, route in
            if screen != 5, !selectedA, index < 3 {
                return nil
            }
            return route.coordinates.map { .init(latitude: $0[0], longitude: $0[1]) }
        }
    }

    var body: some View {
        GeometryReader { _ in
            let region = MKCoordinateRegion(
                center: .init(latitude: 34.9871, longitude: 135.7596),
                span: .init(latitudeDelta: 0.0038, longitudeDelta: 0.0052))
            Map(initialPosition: .region(region), interactionModes: []) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, points in
                    MapPolyline(coordinates: points).stroke(index >= 3 ? .gray : Theme.ink, lineWidth: 4)
                }
                Annotation("京都駅前", coordinate: FenrirCapture.station, anchor: .bottom) { pin("S") }
                Annotation("ホテル", coordinate: FenrirCapture.hotelPoint, anchor: .top) { pin("1") }
                    .annotationTitles(.hidden)
                if screen == 5 || selectedA {
                    Annotation("イノダコーヒ", coordinate: FenrirCapture.cafeAPoint) { pin("A") }
                }
                if screen == 5 || !selectedA {
                    Annotation("OGAWA COFFEE", coordinate: FenrirCapture.cafeBPoint) { pin("B") }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        }
    }

    private func pin(_ title: String) -> some View {
        Text(title).font(Theme.latin(13, .bold)).foregroundStyle(.white)
            .frame(width: 29, height: 29).background(Theme.ink, in: .circle)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}
#endif
