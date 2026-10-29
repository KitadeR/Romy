import MapKit
import SwiftUI

/// What Romy can show of a place it did not choose a photo for (2026-10-29, るわさん「24みたいな感じで写真は
/// 表示できない？」→「1と2で試す」). Apple does not give out its place photos for an app's own cards, so the card
/// shows Apple's Look Around picture of the street in front of the place, when Apple has one, and the place's
/// photos, hours and the rest are in Apple's own place card (`MKMapItemDetailViewController`).
enum PlacePhotos {
    /// Pictures already asked for, by place; a place without Look Around keeps its nil so it is not asked again.
    @MainActor private static var lookArounds: [String: UIImage?] = [:]

    /// Apple's Look Around picture at the place, or nil where Apple has none or nothing came back.
    @MainActor static func lookAround(of place: ProposalPlace, size: CGSize) async -> UIImage? {
        let key = "\(place.latitude),\(place.longitude)"
        if let kept = lookArounds[key] { return kept }
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let image: UIImage?
        if let scene = try? await MKLookAroundSceneRequest(coordinate: coordinate).scene {
            let options = MKLookAroundSnapshotter.Options()
            options.size = size
            image = try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image
        } else {
            image = nil
        }
        guard !Task.isCancelled else { return nil }
        lookArounds[key] = image
        return image
    }

    /// Apple's own record of the place, for its place card; nil without Apple's place ID.
    static func mapItem(of place: ProposalPlace) async -> MKMapItem? {
        guard let id = place.placeID.flatMap(MKMapItem.Identifier.init(rawValue:)) else { return nil }
        return try? await MKMapItemRequest(mapItemIdentifier: id).mapItem
    }
}

/// The Look Around picture of a place, or nothing at all where Apple has none (the card then looks as before).
struct LookAroundPicture: View {
    let place: ProposalPlace
    var height: CGFloat = 112
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                // The picture fills a frame the card decides, so it never widens the card.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay { Image(uiImage: image).resizable().scaledToFill() }
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(alignment: .bottomLeading) {
                        Text("Look Around").font(Theme.latin(10, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.45), in: .capsule)
                            .padding(8)
                    }
                    .accessibilityLabel("\(place.name)の前の通りの写真（Look Around）")
            } else {
                // Takes no room, but is there so the picture is asked for (an empty view runs no task).
                Color.clear.frame(height: 0)
            }
        }
        .task(id: "\(place.latitude),\(place.longitude)") {
            image = await PlacePhotos.lookAround(of: place, size: CGSize(width: 600, height: height * 2))
        }
    }
}

/// Apple's place card for a place (photos, hours, phone), presented from Romy's summary.
struct AppleMapItemDetail: UIViewControllerRepresentable {
    let item: MKMapItem
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    func makeUIViewController(context: Context) -> MKMapItemDetailViewController {
        let controller = MKMapItemDetailViewController(mapItem: item, displaysMap: false)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MKMapItemDetailViewController, context: Context) {}

    final class Coordinator: NSObject, MKMapItemDetailViewControllerDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }

        func mapItemDetailViewControllerDidFinish(_ detailViewController: MKMapItemDetailViewController) {
            onClose()
        }
    }
}
