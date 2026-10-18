import CoreLocation
import MapKit
import Observation

/// Apple's search for places to add as plans (Notion 02 §6-6 ＋ボタン ①, Figma 15-3).
/// Results lean toward the trip's destinations. One search runs after typing pauses, since Apple limits
/// how often a device may search (Notion 05, 2026-10-14).
///
/// A search for a wide name such as 「東京」 returns only the area itself (東京都), so the completer, which is
/// meant for typing, adds suggestions (東京駅, 東京タワー…). When the typed text is an area, the completer is
/// pointed at that area, otherwise it leans toward the trip's destinations (it would follow the device).
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    struct Result: Identifiable, Hashable {
        let id: String
        let title: String
        /// 「名所」「駅」「カフェ」, or 「場所」 for an address.
        let category: String
        let kind: PlanKind
        /// Town from the address (「京都市」), shown next to the category.
        let town: String?
        /// The place. Nil for a suggestion from the completer, which is looked up when it is added (`resolve`).
        var item: MKMapItem?
        var completion: MKLocalSearchCompletion?

        var detail: String {
            guard let town, !town.isEmpty else { return category }
            return "\(category) ・ \(town)"
        }
    }

    private(set) var results: [Result] = []
    private var region: MKCoordinateRegion?
    private var task: Task<Void, Never>?
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    /// The suggestions being waited for; one request at a time.
    @ObservationIgnored private var waiting: CheckedContinuation<[MKLocalSearchCompletion], Never>?
    @ObservationIgnored private var waitingToken = 0

    override init() {
        super.init()
        completer.delegate = self
        // Not 「近くを検索」 suggestions (.query): they are searches, not places.
        completer.resultTypes = [.pointOfInterest, .address]
    }

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
            let nearby = region ?? Self.japan
            async let searched = Self.search(trimmed, near: region)
            async let suggested = suggestions(for: trimmed, in: nearby)
            let found = await searched
            var suggestions = await suggested
            // The typed text is an area (「東京」): ask the completer about that area instead.
            if let center = Self.areaCenter(in: found, matching: trimmed), !Task.isCancelled {
                suggestions = await self.suggestions(for: trimmed, in: Self.areaRegion(around: center))
            }
            guard !Task.isCancelled else { return }
            results = Self.merge(suggestions: suggestions.map(Self.result(from:)), found: found)
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
            guard let result = result(from: item), seen.insert(result.id).inserted else { return nil }
            return result
        }
    }

    static func result(from item: MKMapItem, fallbackTitle: String? = nil) -> Result? {
        guard let name = item.name.flatMap({ $0.isEmpty ? nil : $0 }) ?? fallbackTitle else { return nil }
        let coordinate = item.location.coordinate
        let id = item.identifier?.rawValue
            ?? String(format: "%@:%.5f,%.5f", name, coordinate.latitude, coordinate.longitude)
        let category = category(of: item)
        let town = town(from: item.address?.fullAddress ?? item.addressRepresentations?.cityName ?? "")
        return Result(id: id, title: name, category: category.label, kind: category.kind, town: town, item: item)
    }

    /// A suggestion from the completer. Its kind is not known until it is looked up when added.
    static func result(from completion: MKLocalSearchCompletion) -> Result {
        Result(
            id: "suggestion:\(completion.title)|\(completion.subtitle)",
            title: completion.title, category: "場所", kind: .other,
            town: town(from: completion.subtitle), item: nil, completion: completion
        )
    }

    /// The place behind a result: a suggestion is looked up with Apple's search; nil when that fails.
    static func resolve(_ result: Result) async -> Result? {
        if result.item != nil { return result }
        guard let completion = result.completion,
              let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
                  .start().mapItems.first else { return nil }
        return Self.result(from: item, fallbackTitle: result.title)
    }

    // MARK: - Suggestions

    /// Where the typed area is, when one of the found places is an area (no place category, 「東京都」)
    /// whose name contains what was typed.
    static func areaCenter(in found: [Result], matching typed: String) -> CLLocationCoordinate2D? {
        found.first { $0.item?.pointOfInterestCategory == nil && AreaSearch.name($0.title, contains: typed) }?
            .item?.location.coordinate
    }

    static func areaRegion(around center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
    }

    /// Suggestions first (they are what people look for by name), each replaced by the found place of the same
    /// name when there is one (it knows its category); then the rest of the found places.
    static func merge(suggestions: [Result], found: [Result], limit: Int = 15) -> [Result] {
        var merged: [Result] = []
        var used = Set<String>()
        for suggestion in suggestions {
            if let match = found.first(where: { $0.title == suggestion.title && !used.contains($0.id) }) {
                used.insert(match.id)
                merged.append(match)
            } else if !merged.contains(where: { $0.title == suggestion.title && $0.town == suggestion.town }) {
                merged.append(suggestion)
            }
        }
        merged += found.filter { !used.contains($0.id) }
        return Array(merged.prefix(limit))
    }

    /// Asks the completer once. A new request ends the one still waiting; no answer in 2 seconds gives none.
    private func suggestions(for query: String, in region: MKCoordinateRegion) async -> [MKLocalSearchCompletion] {
        finish([])
        completer.cancel()
        completer.region = region
        waitingToken += 1
        let token = waitingToken
        return await withCheckedContinuation { continuation in
            waiting = continuation
            completer.queryFragment = query
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if self?.waitingToken == token { self?.finish([]) }
            }
        }
    }

    private func finish(_ completions: [MKLocalSearchCompletion]) {
        waiting?.resume(returning: completions)
        waiting = nil
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = Array(completer.results.prefix(10))
        Task { @MainActor in self.finish(found) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.finish([]) }
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
