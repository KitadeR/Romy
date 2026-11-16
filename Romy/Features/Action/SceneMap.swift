import MapKit
import SwiftUI

struct SceneMap: View {
    let input: SceneInput
    let options: [SceneOption]
    let selectedID: String
    let routes: SceneRoutes
    @Binding var position: MapCameraPosition
    let onSelect: (String) -> Void

    var body: some View {
        Map(position: $position) {
            if let option = options.first(where: { $0.id == selectedID }) {
                ForEach(legs(of: option), id: \.self) { key in
                    if let route = routes.routes[key] {
                        MapPolyline(route.polyline)
                            .stroke(Theme.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                }
                ForEach(landmarks(of: option), id: \.place.scenePlaceKey) { step in
                    Marker(step.title, systemImage: step.kind == .next ? "flag.fill" : "bag.fill",
                           coordinate: step.place.location.coordinate).tint(.secondary)
                }
            }
            ForEach(pins, id: \.place.scenePlaceKey) { pin in
                Annotation(pin.place.name, coordinate: pin.place.location.coordinate, anchor: .bottom) {
                    if let first = pin.ids.first, pin.ids.count == 1 {
                        Button { onSelect(first) } label: { pinLabel(pin) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(pin.place.name)、\(first)の案")
                    } else {
                        Menu {
                            ForEach(pin.ids, id: \.self) { id in
                                Button("\(id)の案") { onSelect(id) }
                            }
                        } label: { pinLabel(pin) }
                        .accessibilityLabel("\(pin.place.name)を通る案")
                    }
                }
                .annotationTitles(.hidden)
            }
            Annotation(input.origin.name, coordinate: input.origin.location.coordinate) {
                Circle().fill(.blue).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.white, lineWidth: 2)).accessibilityLabel(input.origin.name)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapScaleView() }
        .onAppear {
            // 比較中は同じ縮尺を保つ。戻ってきたときも手動で動かした地図を引き継ぐ。
            if position == .automatic { position = overview }
        }
    }

    private struct Pin {
        let place: ProposalPlace
        var ids: [String]
    }

    private var pins: [Pin] {
        var pins: [Pin] = []
        for option in options {
            guard let place = option.way.seatPlace ?? option.way.steps.first?.place else { continue }
            if let index = pins.firstIndex(where: { $0.place.latitude == place.latitude
                && $0.place.longitude == place.longitude }) {
                pins[index].ids.append(option.id)
            } else {
                pins.append(Pin(place: place, ids: [option.id]))
            }
        }
        return pins
    }

    private func pinLabel(_ pin: Pin) -> some View {
        let active = pin.ids.contains(selectedID)
        return Text(pin.ids.joined(separator: "·"))
            .font(Theme.latin(13, .bold)).padding(.horizontal, 10).frame(minWidth: 30, minHeight: 30)
            .foregroundStyle(active ? Theme.surface : Theme.ink)
            .background(active ? Theme.ink : Theme.surface, in: .capsule)
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            .frame(minWidth: 44, minHeight: 44)
    }

    private func legs(of option: SceneOption) -> [SceneRouteKey] {
        let points = [input.origin] + option.way.steps.map(\.place)
        var seen: Set<SceneRouteKey> = []
        return zip(points, points.dropFirst()).map { SceneRouteKey($0, $1) }.filter { seen.insert($0).inserted }
    }

    private func landmarks(of option: SceneOption) -> [SceneStep] {
        var seen = Set(pins.map { $0.place.scenePlaceKey })
        return option.way.steps.filter { seen.insert($0.place.scenePlaceKey).inserted }
    }

    private var overview: MapCameraPosition {
        let places = [input.origin] + options.flatMap { $0.way.steps.map(\.place) }
        var bounds = MKMapRect.null
        for place in places {
            let point = MKMapPoint(place.location.coordinate)
            bounds = bounds.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        for key in options.flatMap(legs) {
            if let route = routes.routes[key] { bounds = bounds.union(route.polyline.boundingMapRect) }
        }
        let padding = 100 * MKMapPointsPerMeterAtLatitude(input.origin.latitude)
        return .rect(bounds.insetBy(dx: -max(padding, bounds.width * 0.2),
                                    dy: -max(padding, bounds.height * 0.25)))
    }
}
