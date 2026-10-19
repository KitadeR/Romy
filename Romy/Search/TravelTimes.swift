import CoreLocation
import MapKit
import Observation

/// One move between two plans with a place: which plans, how, and where (Notion 02 §6-5 ②移動の行).
/// It is the key of the cache, so a changed place or mode asks Apple again.
struct TravelMove: Hashable {
    let fromID: UUID
    let toID: UUID
    let mode: TravelMode
    let fromLatitude: Double
    let fromLongitude: Double
    let toLatitude: Double
    let toLongitude: Double

    /// The same move by another way of going.
    func with(mode: TravelMode) -> TravelMove {
        TravelMove(
            fromID: fromID, toID: toID, mode: mode, fromLatitude: fromLatitude, fromLongitude: fromLongitude,
            toLatitude: toLatitude, toLongitude: toLongitude
        )
    }

    var straightMeters: Double {
        CLLocation(latitude: fromLatitude, longitude: fromLongitude)
            .distance(from: CLLocation(latitude: toLatitude, longitude: toLongitude))
    }
}

/// Travel times between the plans of a day from MapKit (walking, car, train), kept for the session.
/// Apple limits how often a device may ask and does not say how often, so each move is asked once and kept.
/// Until an answer comes, or when there is none, nothing is counted and nothing is invented (Notion 05).
@Observable
final class TravelTimes {
    enum Result: Equatable {
        case loading
        case ready(TravelEstimate)
        case unavailable
    }

    private(set) var results: [TravelMove: Result] = [:]

    /// The move from one plan to the next; nil when either has no place. The mode is the person's choice for the
    /// move, or walking for a short one and the train for a long one.
    static func move(from origin: ItineraryItem, to destination: ItineraryItem) -> TravelMove? {
        guard let fromLatitude = origin.latitude, let fromLongitude = origin.longitude,
              let toLatitude = destination.latitude, let toLongitude = destination.longitude else { return nil }
        let straight = CLLocation(latitude: fromLatitude, longitude: fromLongitude)
            .distance(from: CLLocation(latitude: toLatitude, longitude: toLongitude))
        return TravelMove(
            fromID: origin.id, toID: destination.id,
            mode: destination.travelMode ?? TravelMode.defaultMode(straightMeters: straight),
            fromLatitude: fromLatitude, fromLongitude: fromLongitude,
            toLatitude: toLatitude, toLongitude: toLongitude
        )
    }

    /// True until Apple has answered (asked, or about to be asked); false once there is an answer or none.
    func isLoading(_ move: TravelMove?) -> Bool {
        guard let move else { return false }
        switch results[move] {
        case nil, .loading: return true
        case .ready, .unavailable: return false
        }
    }

    func store(_ result: Result?, for move: TravelMove) {
        results[move] = result
    }

    func estimate(for move: TravelMove?) -> TravelEstimate? {
        guard let move, case .ready(let estimate) = results[move] else { return nil }
        return estimate
    }

    /// Minutes to count between two plans; 0 until Apple has answered.
    func minutes(from origin: ItineraryItem, to destination: ItineraryItem) -> Int {
        estimate(for: Self.move(from: origin, to: destination))?.minutes ?? 0
    }

    /// Asks Apple for the moves not asked yet, one after another.
    func load(_ moves: [TravelMove]) async {
        for move in moves where results[move] == nil {
            store(.loading, for: move)
            let answer = await Self.fetch(move)
            // A cancelled task (the list went away) did not get a real answer; ask again next time.
            store(Task.isCancelled ? nil : answer, for: move)
        }
    }

    private static func fetch(_ move: TravelMove) async -> Result {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: move.fromLatitude, longitude: move.fromLongitude), address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(latitude: move.toLatitude, longitude: move.toLongitude), address: nil
        )
        request.transportType = move.mode.transportType
        guard let response = try? await MKDirections(request: request).calculateETA() else { return .unavailable }
        let estimate = TravelEstimate(seconds: response.expectedTravelTime, meters: response.distance)
        return estimate.isPlausible(straightMeters: move.straightMeters) ? .ready(estimate) : .unavailable
    }
}
