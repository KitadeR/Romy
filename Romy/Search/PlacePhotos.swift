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
        // The outer optional is the dictionary entry; keep an inner nil for places without imagery.
        lookArounds[key] = .some(image)
        return image
    }

    /// Apple's own record of the place, for its place card; nil without Apple's place ID.
    static func mapItem(of place: ProposalPlace) async -> MKMapItem? {
        guard let id = place.placeID.flatMap(MKMapItem.Identifier.init(rawValue:)) else { return nil }
        return try? await MKMapItemRequest(mapItemIdentifier: id).mapItem
    }
}

/// The Look Around picture of a place. The frame keeps the same height while loading and where Apple has no
/// imagery (2026-11-19, るわさん「写真ない場合でも、同じ下の位置に合わせるべき」), so the lines under it never move.
/// The caller owns `picture`, so a card can show the rest of itself as loading too.
struct LookAroundPicture: View {
    let place: ProposalPlace
    var kind: SceneStep.Kind = .rest
    var height: CGFloat = 112
    let picture: LookAroundPictureModel

    var body: some View {
        Group {
            switch picture.phase(for: place) {
            case .loading:
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.rangeFill)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .modifier(Shimmer())
                    .accessibilityLabel("\(place.name)の周辺の写真を読み込み中")
            case let .available(image):
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
            case .unavailable:
                // A completed lookup without imagery says so in the same frame, not with an endless placeholder.
                NoPicture(kind: kind, text: "通りの写真はありません", height: height)
            }
        }
        .task(id: LookAroundPictureModel.key(for: place)) {
            await picture.load(place, size: CGSize(width: 600, height: height * 2))
        }
    }
}

/// The frame a picture would fill, with the kind of stop and a short line, for places without one.
struct NoPicture: View {
    let kind: SceneStep.Kind
    let text: String
    var height: CGFloat = 112

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: kind.pictureSymbol).font(.system(size: 24, weight: .regular))
            Text(text).font(Theme.jp(12))
        }
        .foregroundStyle(Theme.actionSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Theme.fill, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

extension SceneStep.Kind {
    /// The symbol a missing picture shows: a cup for a rest, a fork and knife for a meal.
    var pictureSymbol: String {
        switch self {
        case .rest: "cup.and.saucer"
        case .eat: "fork.knife"
        case .dropLuggage, .lockerDrop, .lockerPickUp: "suitcase.rolling"
        case .checkIn: "bed.double"
        case .next: "mappin.and.ellipse"
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
