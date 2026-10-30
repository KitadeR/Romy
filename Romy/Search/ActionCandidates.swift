import CoreLocation
import MapKit

/// Apple's map behind the Action proposal: places for a chip and walking times.
enum MapKitActionSearch {
    /// Our kind of place → Apple's. Convenience stores come back as food markets (Notion 05, 2026-10-19).
    static let categories: [String: MKPointOfInterestCategory] = [
        "bakery": .bakery, "cafe": .cafe, "restaurant": .restaurant, "convenience": .foodMarket,
        "park": .park, "beach": .beach
    ]

    /// Places for a query. Finding nothing is an empty list; not being able to ask (no network) throws.
    static func search(_ query: CandidateQuery) async throws -> [ProposalPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.text
        request.resultTypes = .pointOfInterest
        if let category = query.category.flatMap({ categories[$0] }) {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [category])
        }
        // The region is only a hint otherwise: a search near 松本 returned shops in 和歌山 (2026-10-19).
        request.regionPriority = .required
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: query.center.latitude, longitude: query.center.longitude),
            span: MKCoordinateSpan(latitudeDelta: query.spanDegrees, longitudeDelta: query.spanDegrees)
        )
        do {
            return try await MKLocalSearch(request: request).start().mapItems.compactMap(place(from:))
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        }
    }

    static func place(from item: MKMapItem) -> ProposalPlace? {
        guard let name = item.name, !name.isEmpty else { return nil }
        let coordinate = item.location.coordinate
        return ProposalPlace(
            name: name, address: item.address?.fullAddress,
            category: item.pointOfInterestCategory.map { $0.rawValue } ?? "none",
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            placeID: item.identifier?.rawValue
        )
    }

    /// Walking minutes between two places from Apple; nil when there is no answer.
    static func walkingMinutes(from start: ProposalPlace, to end: ProposalPlace) async -> Int? {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: start.location, address: nil)
        request.destination = MKMapItem(location: end.location, address: nil)
        request.transportType = .walking
        guard let eta = try? await MKDirections(request: request).calculateETA() else { return nil }
        return Int((eta.expectedTravelTime / 60).rounded(.up))
    }
}
