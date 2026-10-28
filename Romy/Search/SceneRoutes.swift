import MapKit
import Observation

/// One directions response supplies both the minutes and the road shape, so the map and calculation agree.
struct SceneRoute {
    let minutes: Int
    let polyline: MKPolyline
}

struct SceneRouteKey: Hashable {
    let fromLatitude: Double
    let fromLongitude: Double
    let toLatitude: Double
    let toLongitude: Double

    init(_ from: ProposalPlace, _ destination: ProposalPlace) {
        fromLatitude = from.latitude
        fromLongitude = from.longitude
        toLatitude = destination.latitude
        toLongitude = destination.longitude
    }
}

@Observable
final class SceneRoutes {
    typealias Fetch = (ProposalPlace, ProposalPlace) async throws -> SceneRoute
    private(set) var routes: [SceneRouteKey: SceneRoute] = [:]
    private var unavailable: Set<SceneRouteKey> = []
    @ObservationIgnored private let fetch: Fetch

    init(fetch: @escaping Fetch = SceneRoutes.fetch) {
        self.fetch = fetch
    }

    func minutes(_ from: ProposalPlace, _ destination: ProposalPlace) async -> Int? {
        let key = SceneRouteKey(from, destination)
        if let route = routes[key] {
            return route.minutes
        }
        if unavailable.contains(key) {
            return nil
        }
        if from.latitude == destination.latitude, from.longitude == destination.longitude {
            return 0
        }
        do {
            let route = try await fetch(from, destination)
            try Task.checkCancellation()
            routes[key] = route
            return route.minutes
        } catch {
            if !Task.isCancelled {
                unavailable.insert(key)
            }
            return nil
        }
    }

    func retryUnavailable() {
        unavailable.removeAll()
    }

    private static func fetch(_ from: ProposalPlace, _ destination: ProposalPlace) async throws -> SceneRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: from.location, address: nil)
        request.destination = MKMapItem(location: destination.location, address: nil)
        request.transportType = .walking
        let directions = MKDirections(request: request)
        let response = try await withTaskCancellationHandler {
            try await directions.calculate()
        } onCancel: { directions.cancel() }
        guard let route = response.routes.first else { throw RouteError.unavailable }
        return SceneRoute(minutes: Int((route.expectedTravelTime / 60).rounded(.up)), polyline: route.polyline)
    }

    private enum RouteError: Error { case unavailable }
}
