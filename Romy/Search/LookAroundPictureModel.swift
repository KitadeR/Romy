import Observation
import UIKit

/// Keeps loading distinct from a place without imagery, and ignores answers for an older request.
/// Loading lasts at least `minimumLoading`, so even a kept picture shows that it was looked up
/// (2026-11-19, るわさん「読み込んだのかどうか気になるため、絶対すぐ表示せずに」).
@Observable @MainActor
final class LookAroundPictureModel {
    enum Phase {
        case loading
        case available(UIImage)
        case unavailable
    }

    typealias Loader = @MainActor (ProposalPlace, CGSize) async -> UIImage?

    private var phase: Phase = .loading
    private var placeKey: String?
    private var generation = 0
    private let loadImage: Loader
    private let minimumLoading: Duration

    init(minimumLoading: Duration = .milliseconds(400), loadImage: @escaping Loader = { place, size in
        await PlacePhotos.lookAround(of: place, size: size)
    }) {
        self.minimumLoading = minimumLoading
        self.loadImage = loadImage
    }

    func phase(for place: ProposalPlace) -> Phase {
        // SwiftUI can render the new place before its task has started.
        placeKey == Self.key(for: place) ? phase : .loading
    }

    func load(_ place: ProposalPlace, size: CGSize) async {
        guard !Task.isCancelled else { return }
        generation += 1
        let mine = generation
        placeKey = Self.key(for: place)
        phase = .loading
        let clock = ContinuousClock()
        let started = clock.now
        let image = await loadImage(place, size)
        let remaining = minimumLoading - (clock.now - started)
        if remaining > .zero { try? await Task.sleep(for: remaining) }
        guard !Task.isCancelled, mine == generation else { return }
        phase = image.map(Phase.available) ?? .unavailable
    }

    static func key(for place: ProposalPlace) -> String {
        "\(place.latitude),\(place.longitude)"
    }
}
