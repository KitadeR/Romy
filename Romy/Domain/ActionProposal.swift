import CoreLocation
import Foundation

// The core of the Action proposal (Notion 02 §6-4, decided 2026-10-19): a wish becomes chips, each chip is looked
// up on the map, and the places are put in a row between two plans with the time counted in code.
// No screen and no AI here; the chips come from outside (a person's edit now, the cheap model later).

/// A place on the map, or an end of the gap (where the person is, the next plan).
struct ProposalPlace: Equatable {
    let name: String
    let address: String?
    let category: String
    let latitude: Double
    let longitude: Double
    /// Apple's place ID, when the place came from Apple's search; it opens Apple's place card (photos, hours).
    let placeID: String?

    init(
        name: String, address: String? = nil, category: String = "none", latitude: Double, longitude: Double,
        placeID: String? = nil
    ) {
        self.name = name
        self.address = address
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.placeID = placeID
    }

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    func meters(to other: ProposalPlace) -> Double { location.distance(from: other.location) }

    /// The two names point at the same place: one holds the other once spaces and branch words are dropped.
    static func sameName(_ map: String, _ said: String) -> Bool {
        func core(_ text: String) -> String {
            var text = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
            for word in [" ", "\u{3000}", "本店", "支店", "店"] { text = text.replacingOccurrences(of: word, with: "") }
            return text
        }
        let (left, right) = (core(map), core(said))
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.contains(right) || right.contains(left)
    }
}

/// One thing the person wants to do, split from the wish.
struct ProposalChip: Equatable {
    /// A concrete chip names a place or a kind of shop (searched on the map); an abstract one is a mood
    /// (「海沿いを歩きたい」), searched later by a location-aware model and then checked on the map.
    enum Kind: String { case concrete, abstract }

    enum Activity: String {
        case buy, eat, rest, see, other

        /// How long the person is assumed to stay, until the plan's own length is known.
        var stayMinutes: Int {
            switch self {
            case .buy: 10
            case .eat: 40
            case .rest: 30
            case .see: 30
            case .other: 20
            }
        }
    }

    let text: String
    let kind: Kind
    let activity: Activity
    /// One or two words for the map's search (a long query found nothing in Kyoto, 2026-10-19).
    let query: String
    /// Our own name for the kind of place (`ActionCandidates.categoryWords`); "none" when it is not one of them.
    let category: String

    init(
        text: String, kind: Kind = .concrete, activity: Activity = .other, query: String? = nil,
        category: String = "none"
    ) {
        self.text = text
        self.kind = kind
        self.activity = activity
        self.query = query ?? text
        self.category = category
    }
}

/// A condition kept apart from the chips, shown as a small gray tag (「あまり歩きたくない」).
struct ProposalCondition: Equatable {
    enum Kind: String { case walkLess, indoor, other }

    let text: String
    let kind: Kind
}

/// The time between where the person is and the next plan.
struct ActionGap: Equatable {
    let origin: ProposalPlace
    let next: ProposalPlace
    /// Minutes from now until the next plan starts. Zero or less when the person is already late.
    let availableMinutes: Int

    /// Time kept for getting in and out of each place and for being late a little.
    static let marginMinutes = 15
}

/// How far the person is willing to walk. Straight-line distance is the filter; the real walking time is
/// counted from Apple for the routes that remain.
enum WalkLimit {
    static let metersPerMinute = 80.0
    static let capMinutes = 15

    /// One way, from where the person is: a quarter of the time there is, at most 15 minutes, halved when the
    /// person said they do not want to walk (provisional, 2026-10-19).
    /// `widerBy` is what 「もう少し遠くも」 adds, in minutes; it may go past the cap, since the person asked.
    static func oneWayMinutes(availableMinutes: Int, walkLess: Bool, widerBy: Int = 0) -> Int {
        let base = min(max(availableMinutes, 0) / 4, capMinutes)
        return (walkLess ? base / 2 : base) + max(widerBy, 0)
    }

    static func meters(minutes: Int) -> Double { Double(minutes) * metersPerMinute }

    /// The width of a map region that covers a circle of this radius (about 111 km a degree).
    static func spanDegrees(radiusMeters: Double) -> Double { max(radiusMeters * 2 / 111_000, 0.005) }
}

/// What a check of one fact found out, shown as ✓ / 紹介されています / ？ / ✗ (Figma 23案).
enum CheckResult: Equatable {
    /// Yes, from the official source.
    case official
    /// Yes, as someone else's page says.
    case introduced
    case unknown
    /// The check found that it is not so.
    case contradicted

    /// Words in a detail that take back a yes («確証はない»). Only the negative forms: «確認できます» is a yes.
    static let doubtWords = ["確証はな", "確証がな", "確認できな", "確認できず", "見つから", "不明", "分から", "特定できな"]

    /// A yes with no source, or one whose detail doubts it, is not believed.
    static func from(answer: String, isOfficial: Bool, sourceCount: Int, detail: String) -> CheckResult {
        switch answer {
        case "no":
            return .contradicted
        case "yes":
            if sourceCount == 0 || doubtWords.contains(where: detail.contains) { return .unknown }
            return isOfficial ? .official : .introduced
        default:
            return .unknown
        }
    }
}
