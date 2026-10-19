import MapKit
import Observation

/// Apple's search for destinations the catalog does not have (Notion 02 §1, widened 2026-10-14):
/// - areas such as 嵐山 or 舞浜: a completer (meant for typing) over addresses and natural features
/// - large sights such as 東京ディズニーリゾート: one search after typing pauses, kept only when its
///   category is in `sightCategories` (the completer's category filter let events through).
///   Apple files some famous sights as plain landmarks (東京ディズニーランド, 清水寺) next to stadiums and
///   signboards, so a landmark is kept only when its name contains what was typed.
@Observable
final class AreaSearch: NSObject, MKLocalSearchCompleterDelegate {
    struct Result: Hashable {
        let title: String
        /// Line under the title, e.g. 「テーマパーク・浦安市」.
        let detail: String
        let kind: Destination.Kind
        let completion: MKLocalSearchCompletion?
        let item: MKMapItem?
    }

    /// Large sights people name a trip after. Shops, stations, shrines and museums stay out;
    /// they are added later as plans.
    static let sightCategories: [MKPointOfInterestCategory: String] = [
        .amusementPark: "テーマパーク",
        .aquarium: "水族館",
        .zoo: "動物園",
        .nationalPark: "国立公園",
        .castle: "城",
        .skiing: "スキー場",
        .landmark: "名所"
    ]

    private(set) var areas: [MKLocalSearchCompletion] = []
    private(set) var sights: [MKMapItem] = []
    private var sightQuery = ""
    private let areaCompleter = MKLocalSearchCompleter()
    private var sightTask: Task<Void, Never>?

    private static let prefectures = Set(DestinationCatalog.bundled.entries.filter(\.isPrefecture).map(\.name))
    private static let japan = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5, longitude: 137.5),
        span: MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 24)
    )

    override init() {
        super.init()
        areaCompleter.delegate = self
        areaCompleter.region = Self.japan
        areaCompleter.regionPriority = .required
        areaCompleter.resultTypes = [.address, .physicalFeature]
    }

    /// Keeps place names in Japan; drops facilities with a street number (「箱根水明荘湯本702」)
    /// and places abroad (「ディズニー アメリカ合衆国」).
    static func isPlace(title: String, subtitle: String) -> Bool {
        !hasNumber(title) && prefectures.contains { subtitle.hasPrefix($0) }
    }

    static func hasNumber(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
    }

    /// The town part of an address, written one way for every result:
    /// 「〒279-8511, 千葉県浦安市舞浜1-1」→「浦安市」, 「箱根町, 足柄下郡」「足柄下郡箱根町」→「箱根町」.
    static func town(from address: String) -> String {
        var rest = Substring(address)
        if !rest.hasPrefix("〒"), let comma = rest.range(of: ", ") {
            rest = rest[..<comma.lowerBound]
        }
        if let comma = rest.firstIndex(of: ","), rest.hasPrefix("〒") {
            rest = rest[rest.index(after: comma)...]
        }
        rest = rest.drop { $0 == " " }
        if let prefecture = prefectures.first(where: { rest.hasPrefix($0) }) {
            rest = rest.dropFirst(prefecture.count)
        }
        if let county = rest.firstIndex(of: "郡") {
            rest = rest[rest.index(after: county)...]
        }
        guard let end = rest.firstIndex(where: { "市区町村".contains($0) }) else {
            return String(rest.prefix { !$0.isNumber })
        }
        return String(rest[...end])
    }

    /// True when the typed text appears in the name, ignoring hiragana/katakana and width:
    /// 「でぃずにー」 matches 「東京ディズニーランド」, 「とうきょう」 does not match 「東京ドーム」.
    static func name(_ name: String, contains query: String) -> Bool {
        func fold(_ text: String) -> String {
            let narrow = text.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? text
            return (narrow.applyingTransform(.hiraganaToKatakana, reverse: false) ?? narrow).lowercased()
        }
        let typed = fold(query.trimmingCharacters(in: .whitespaces))
        return !typed.isEmpty && fold(name).contains(typed)
    }

    /// Prefecture and town for an area: 「愛知県大府市, 横根町」→「愛知県大府市」.
    static func area(from subtitle: String) -> String {
        subtitle.components(separatedBy: ", ").first ?? subtitle
    }

    /// Sights first (they are what people look for by name), then areas.
    var results: [Result] {
        let sightResults = sights.compactMap { item -> Result? in
            guard let name = item.name, let category = item.pointOfInterestCategory,
                  let label = Self.sightCategories[category] else { return nil }
            if category == .landmark, !Self.name(name, contains: sightQuery) { return nil }
            let town = Self.town(from: item.addressRepresentations?.cityName ?? item.address?.fullAddress ?? "")
            return Result(
                title: name,
                detail: Destination.detail(kind: .landmark, name: name, context: town, category: label),
                kind: .landmark, completion: nil, item: item
            )
        }
        let areaResults = areas.filter { Self.isPlace(title: $0.title, subtitle: $0.subtitle) }.map {
            Result(
                title: $0.title,
                detail: Destination.detail(
                    kind: .area, name: $0.title, context: Self.area(from: $0.subtitle), category: nil
                ),
                kind: .area, completion: $0, item: nil
            )
        }
        return Self.nameMatchesFirst(sightResults, query: sightQuery) + areaResults
    }

    /// At most 5 sights, those whose name contains what was typed first. Apple also returns sights that only
    /// loosely fit (「東京駅」 gives theme parks too); without this they filled all 5 and pushed 東京駅 out.
    static func nameMatchesFirst(_ sights: [Result], query: String, limit: Int = 5) -> [Result] {
        let matches = sights.filter { name($0.title, contains: query) }
        let others = sights.filter { !name($0.title, contains: query) }
        return Array((matches + others).prefix(limit))
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        sightTask?.cancel()
        guard trimmed.count >= 2 else {
            areaCompleter.cancel()
            areas = []
            sights = []
            return
        }
        areaCompleter.queryFragment = trimmed
        sightTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let found = await Self.searchSights(trimmed)
            guard !Task.isCancelled else { return }
            self?.sightQuery = trimmed
            self?.sights = found
        }
    }

    /// Two searches: asking for landmarks together with theme parks changes what Apple returns
    /// (「でぃずにー」 then gives only the land, not the sea or the resort), so they are asked apart.
    private static func searchSights(_ query: String) async -> [MKMapItem] {
        let typed = Array(sightCategories.keys.filter { $0 != .landmark })
        async let parks = search(query, categories: typed)
        async let landmarks = search(query, categories: [.landmark])
        return await parks + landmarks
    }

    private static func search(_ query: String, categories: [MKPointOfInterestCategory]) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        request.region = japan
        request.regionPriority = .required
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        return Array(items.prefix(10))
    }

    /// Turns a result into a destination with its location.
    func destination(for result: Result) async -> Destination? {
        let item: MKMapItem
        if let found = result.item {
            item = found
        } else if let completion = result.completion,
                  let found = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
                      .start().mapItems.first {
            item = found
        } else {
            return nil
        }
        let coordinate = item.location.coordinate
        let context: String? = switch result.kind {
        case .landmark: Self.town(from: item.addressRepresentations?.cityName ?? "")
        default: Self.area(from: result.completion?.subtitle ?? "")
        }
        return Destination(
            id: String(
                format: "%@:%@:%.4f,%.4f",
                result.kind.rawValue, result.title, coordinate.latitude, coordinate.longitude
            ),
            name: result.title,
            context: context?.isEmpty == true ? nil : context,
            kind: result.kind,
            category: item.pointOfInterestCategory.flatMap { Self.sightCategories[$0] },
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = Array(completer.results.prefix(8))
        Task { @MainActor in self.areas = found }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.areas = [] }
    }
}
