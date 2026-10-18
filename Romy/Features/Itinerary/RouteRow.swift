import MapKit
import SwiftUI

/// The move between two plans (Notion 02 §6-5 ②移動の行), drawn like Rhyme's: a small grey chip in the card column
/// with the way of going, the time and the distance (「電車 13分 ・ 10.3km」); tapping it opens three tiles to
/// choose walking, car or train, each with its own time. A round button on the right opens the route in Apple
/// Maps in that mode. The chip begins where the cards do, so it never lies over the time line.
/// Until MapKit has answered, or when it has none, only the way of going is shown. Choosing Google Maps and
/// roads on the map come later (Notion 05). 未定 has no order of visits, so it has no moves; plans without a
/// place have no route.
struct RouteRow: View {
    let origin: ItineraryItem
    let destination: ItineraryItem
    let isOnADay: Bool
    let travel: TravelTimes
    /// The time line passing through this move; it continues the line of the plan before (nil in 未定).
    let line: TimeLineStyle?
    /// The day's color when this is the move from 今 to the next plan (Notion 02 §6-5); nil otherwise.
    var highlight: Color?

    @State private var isChoosing = false

    var body: some View {
        Group {
            if isOnADay, let move = TravelTimes.move(from: origin, to: destination),
               let start = RouteLink.mapItem(origin), let end = RouteLink.mapItem(destination) {
                HStack(spacing: 8) {
                    // The cards start after the time column; so does the chip.
                    Color.clear.frame(width: TimeLineLayout.timeWidth + TimeLineLayout.rowSpacing, height: 1)
                    chip(move)
                    Spacer(minLength: 8)
                    directionButton(move, start: start, end: end)
                }
                .padding(.vertical, 2)
            } else {
                Color.clear.frame(height: 4)
            }
        }
        .background { if isOnADay, let line { TimeLine(style: line) } }
    }

    /// 「電車 13分 ・ 10.3km」 with the arrows of a menu.
    private func chip(_ move: TravelMove) -> some View {
        let estimate = travel.estimate(for: move)
        let text = estimate.map { "\(move.mode.label) \($0.durationText) ・ \($0.distanceText)" } ?? move.mode.label
        return Button { isChoosing = true } label: {
            HStack(spacing: 6) {
                Image(systemName: move.mode.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(move.mode.tint)
                Text(text)
                    .font(Theme.jp(12, .bold))
                    .foregroundStyle(Theme.ink)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Theme.fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("移動の手段、\(text)")
        .popover(isPresented: $isChoosing) {
            tiles(move)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Walking, car and train side by side, each with its time and distance; the chosen one is shaded.
    private func tiles(_ move: TravelMove) -> some View {
        HStack(spacing: 8) {
            ForEach(TravelMode.allCases, id: \.self) { mode in
                let estimate = travel.estimate(for: move.with(mode: mode))
                Button {
                    destination.travelMode = mode
                    isChoosing = false
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(mode.tint)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(mode.tint.opacity(0.14)))
                        Text(estimate?.durationText ?? mode.label)
                            .font(Theme.jp(14, .bold))
                            .foregroundStyle(Theme.ink)
                        Text(estimate?.distanceText ?? " ")
                            .font(Theme.jp(11, .medium))
                            .foregroundStyle(Theme.secondary)
                    }
                    .frame(width: 78)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(mode == move.mode ? Theme.fill : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(mode.label)\(estimate.map { "、\($0.durationText)、\($0.distanceText)" } ?? "")"
                )
                .accessibilityAddTraits(mode == move.mode ? .isSelected : [])
            }
        }
        .padding(10)
        // Asks for all three once the tiles are shown (already known ones are kept).
        .task { await travel.load(TravelMode.allCases.map { move.with(mode: $0) }) }
    }

    /// The round button: the route in Apple Maps by the chosen mode. It takes the day's color on the move from 今.
    private func directionButton(_ move: TravelMove, start: MKMapItem, end: MKMapItem) -> some View {
        Button { RouteLink.open(from: start, to: end, mode: move.mode) } label: {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(highlight == nil ? Theme.ink : .white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(highlight ?? Theme.fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(origin.title)から\(destination.title)への経路（\(move.mode.label)）")
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

    static func open(from origin: MKMapItem, to destination: MKMapItem, mode: TravelMode? = nil) {
        MKMapItem.openMaps(
            with: [origin, destination],
            launchOptions: [MKLaunchOptionsDirectionsModeKey: mode?.launchMode ?? MKLaunchOptionsDirectionsModeDefault]
        )
    }

    /// The route to a place from `origin`, or from where the person is when there is none.
    static func open(to destination: MKMapItem, from origin: MKMapItem?, mode: TravelMode? = nil) {
        guard let origin else {
            MKMapItem.openMaps(
                with: [destination],
                launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault]
            )
            return
        }
        open(from: origin, to: destination, mode: mode)
    }
}
