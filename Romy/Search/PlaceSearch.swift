import CoreLocation
import MapKit
import Observation

/// Apple's search for places to add as plans (Notion 02 §6-6 ＋ボタン ①, Figma 15-3).
/// Results lean toward the trip's destinations. One search runs after typing pauses, since Apple limits
/// how often a device may search (Notion 05, 2026-10-14).
@Observable
final class PlaceSearch {
    struct Result: Identifiable, Hashable {
        let id: String
        let title: String
        /// 「名所」「駅」「カフェ」, or 「場所」 for an address.
        let category: String
        let kind: PlanKind
        /// Town from the address (「京都市」), shown next to the category.
        let town: String?
        let item: MKMapItem

        var detail: String {
            guard let town, !town.isEmpty else { return category }
            return "\(category) ・ \(town)"
        }
    }

    private(set) var results: [Result] = []
    private var region: MKCoordinateRegion?
    private var task: Task<Void, Never>?

    static let japan = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5, longitude: 137.5),
        span: MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 24)
    )

    /// Kind of place as Apple names it → the Japanese word and the broad kind.
    /// Anything not listed is 「場所」・その他.
    static let categories: [MKPointOfInterestCategory: (label: String, kind: PlanKind)] = [
        .amusementPark: ("テーマパーク", .sight),
        .aquarium: ("水族館", .sight),
        .zoo: ("動物園", .sight),
        .museum: ("博物館・美術館", .sight),
        .nationalPark: ("国立公園", .sight),
        .park: ("公園", .sight),
        .castle: ("城", .sight),
        .fortress: ("城跡", .sight),
        .landmark: ("名所", .sight),
        .nationalMonument: ("名所", .sight),
        .beach: ("海辺", .sight),
        .planetarium: ("プラネタリウム", .sight),
        .hiking: ("ハイキング", .sight),
        .skiing: ("スキー場", .sight),
        .spa: ("温泉・スパ", .sight),
        .stadium: ("競技場", .sight),
        .theater: ("劇場", .sight),
        .movieTheater: ("映画館", .sight),
        .musicVenue: ("ライブ会場", .sight),
        .restaurant: ("飲食店", .food),
        .cafe: ("カフェ", .food),
        .bakery: ("パン屋", .food),
        .brewery: ("醸造所", .food),
        .winery: ("ワイナリー", .food),
        .distillery: ("蒸留所", .food),
        .nightlife: ("夜の店", .food),
        .foodMarket: ("食品・市場", .shopping),
        .store: ("店", .shopping),
        .hotel: ("宿", .stay),
        .campground: ("キャンプ場", .stay),
        .publicTransport: ("駅", .transport),
        .airport: ("空港", .transport)
    ]

    static func category(of item: MKMapItem) -> (label: String, kind: PlanKind) {
        item.pointOfInterestCategory.flatMap { categories[$0] } ?? ("場所", .other)
    }

    /// Finds where the trip's destinations are once, so results near them come first.
    /// Catalog destinations (prefectures, towns) have no location yet, so they are looked up by name.
    func prepare(for destinations: [Destination]) async {
        region = Self.region(around: await Self.coordinates(of: destinations))
    }

    /// Where the destinations are. Catalog entries have no location yet, so they are looked up by name.
    static func coordinates(of destinations: [Destination]) async -> [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        for destination in destinations {
            if let latitude = destination.latitude, let longitude = destination.longitude {
                points.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            } else if let found = await locate(destination) {
                points.append(found)
            }
        }
        return points
    }

    /// A region covering the points with some room; nil when there are none (then all of Japan).
    static func region(around points: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = points.first else { return nil }
        var (minLat, maxLat, minLon, maxLon) = (first.latitude, first.latitude, first.longitude, first.longitude)
        for point in points.dropFirst() {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.5, 0.4),
                longitudeDelta: max((maxLon - minLon) * 1.5, 0.4)
            )
        )
    }

    private static func locate(_ destination: Destination) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = (destination.context ?? "") + destination.name
        request.resultTypes = .address
        request.region = japan
        request.regionPriority = .required
        return try? await MKLocalSearch(request: request).start().mapItems.first?.location.coordinate
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.cancel()
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            let found = await Self.search(trimmed, near: region)
            guard !Task.isCancelled else { return }
            results = found
        }
    }

    private static func search(_ query: String, near region: MKCoordinateRegion?) async -> [Result] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        request.region = region ?? japan
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        var seen = Set<String>()
        return items.prefix(15).compactMap { item in
            guard let name = item.name, !name.isEmpty else { return nil }
            let coordinate = item.location.coordinate
            let id = item.identifier?.rawValue
                ?? String(format: "%@:%.5f,%.5f", name, coordinate.latitude, coordinate.longitude)
            guard seen.insert(id).inserted else { return nil }
            let category = category(of: item)
            let town = Self.town(from: item.address?.fullAddress ?? item.addressRepresentations?.cityName ?? "")
            return Result(id: id, title: name, category: category.label, kind: category.kind, town: town, item: item)
        }
    }

    /// Town from an address, kept only when it really is a town (「清水町」「京都市」).
    /// An address without one would otherwise give the place's own name or a postcode.
    static func town(from address: String) -> String? {
        let town = AreaSearch.town(from: address)
        guard let last = town.last, "市区町村".contains(last), !AreaSearch.hasNumber(town) else { return nil }
        return town
    }

    /// The ward used to group places, looked up once when a place is saved (Notion 05, 2026-10-14, 案A):
    /// 「京都市」+「東山区」→「京都市東山区」. Tokyo's wards come as the locality (「港区」) and stay as they are.
    /// Without a ward, the city.
    static func ward(locality: String?, subLocality: String?) -> String? {
        guard let locality, !locality.isEmpty else { return nil }
        if locality.hasSuffix("区") { return locality }
        if let subLocality, subLocality.hasSuffix("区") { return locality + subLocality }
        return locality
    }

    /// CLGeocoder is deprecated in iOS 26, but MapKit's newer lookup has no ward field (Notion 05, 2026-10-14).
    /// It is asked once per saved place.
    static func lookUpWard(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let placemark = try? await CLGeocoder()
            .reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ja_JP")).first
        return ward(locality: placemark?.locality, subLocality: placemark?.subLocality)
    }
}
