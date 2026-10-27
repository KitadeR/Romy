import MapKit
import SwiftUI

struct SceneMap: View {
    let input: SceneInput
    let options: [SceneOption]
    let selectedID: String?
    let routes: SceneRoutes
    let onSelect: (String) -> Void
    @State private var position: MapCameraPosition = .automatic

    private var visible: [SceneOption] {
        if let selectedID {
            return options.filter { $0.id == selectedID }
        }
        return options
    }

    var body: some View {
        Map(position: $position) {
            ForEach(visible) { option in
                ForEach(legs(option.way)) { leg in
                    if let route = routes.routes[leg.id] {
                        MapPolyline(route.polyline)
                            .stroke(
                                option.id == (selectedID ?? options.first?.id) ? Theme.ink : Color.gray.opacity(0.45),
                                style: StrokeStyle(lineWidth: option.id == (selectedID ?? options.first?.id) ? 5 : 3,
                                                   lineCap: .round)
                            )
                    }
                }
                if let rest = option.way.steps
                    .first(where: { $0.kind == .rest || $0.kind == .eat || $0.kind == .checkIn }) {
                    Annotation(
                        "\(option.id) 約\(DurationText.text(minutes: option.way.sitMinutes))",
                        coordinate: coordinate(rest.place),
                        anchor: .bottom
                    ) {
                        Button { onSelect(option.id) } label: {
                            Text("\(option.id) 約\(DurationText.text(minutes: option.way.sitMinutes))")
                                .font(Theme.jp(11, .bold))
                                .foregroundStyle(option.id == (selectedID ?? options.first?.id) ? .white : Theme.ink)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(
                                    option.id == (selectedID ?? options.first?.id) ? Theme.ink : Theme.surface,
                                    in: .capsule
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(option.id)の案、座って休める時間は約\(DurationText.text(minutes: option.way.sitMinutes))"
                        )
                        .padding(.bottom, 32)
                    }
                    .annotationTitles(.hidden)
                }
            }
            ForEach(pins) { pin in
                Annotation(pin.place.name, coordinate: coordinate(pin.place)) {
                    Text(pin.emoji).font(.system(size: 14))
                        .frame(width: 30, height: 30)
                        .background(Theme.surface, in: .circle)
                        .overlay(Circle().strokeBorder(Theme.ink,
                                                       style: StrokeStyle(
                                                           lineWidth: 1.5,
                                                           dash: pin.unknown ? [3, 3] : []
                                                       )))
                        .accessibilityLabel("\(pin.place.name)\(pin.unknown ? "、未確認" : "")")
                }
                .annotationTitles(.hidden)
            }
            Annotation(input.origin.name, coordinate: coordinate(input.origin)) {
                Circle().fill(.blue).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .accessibilityLabel(input.origin.name)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .onChange(of: selectedID) { position = .automatic }
        .accessibilityLabel("候補の徒歩経路。所要時間は下の案でも確認できます")
    }

    private func coordinate(_ place: ProposalPlace) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    }

    private struct Leg: Identifiable { let id: SceneRouteKey }

    private func legs(_ way: SceneWay) -> [Leg] {
        let points = [input.origin] + way.steps.map(\.place)
        var seen: Set<SceneRouteKey> = []
        return zip(points, points.dropFirst()).compactMap {
            let key = SceneRouteKey($0, $1)
            return seen.insert(key).inserted ? Leg(id: key) : nil
        }
    }

    private struct Pin: Identifiable {
        let id: String
        let place: ProposalPlace
        let emoji: String
        var unknown: Bool
    }

    private var pins: [Pin] {
        var result: [Pin] = []
        for step in visible.flatMap(\.way.steps) {
            let key = "\(step.place.latitude),\(step.place.longitude)"
            if let index = result.firstIndex(where: { $0.id == key }) {
                result[index].unknown = result[index].unknown || step.isUnknown
            } else {
                result.append(Pin(id: key, place: step.place, emoji: step.kind.emoji, unknown: step.isUnknown))
            }
        }
        return result
    }
}
