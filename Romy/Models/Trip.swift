import Foundation
import SwiftData

/// One trip — the app is a dedicated space per trip (Notion 02 §6).
@Model
final class Trip {
    var id: UUID
    var name: String
    /// True when the name was generated because the person left it blank (Notion 02 §1).
    var isNameAuto: Bool
    var destinations: [Destination]
    /// Stored pieces of `TripDates`; use `dates` instead of these.
    var dateKind: String
    var dayCount: Int?
    var startDate: Date?
    var endDate: Date?
    var createdAt: Date
    var lastOpenedAt: Date
    /// Cover photo chosen by the person (Notion 02 §6-3). Nil until chosen; the automatic photo comes later.
    @Attribute(.externalStorage) var photo: Data?
    /// When each day starts, in minutes after midnight (「1日の始まり」). Guessed times count from here.
    var dayStartMinutes: Int = 9 * 60
    /// Plans on the days and in 未定 (Notion 02 §5).
    @Relationship(deleteRule: .cascade, inverse: \ItineraryItem.trip) var items: [ItineraryItem] = []
    /// Places saved with ♥ in 「行きたい」 (Notion 02 §6-6).
    @Relationship(deleteRule: .cascade, inverse: \WishPlace.trip) var wishes: [WishPlace] = []

    init(name: String, isNameAuto: Bool, destinations: [Destination], dates: TripDates, now: Date = .now) {
        self.id = UUID()
        self.name = name
        self.isNameAuto = isNameAuto
        self.destinations = destinations
        self.dateKind = ""
        self.createdAt = now
        self.lastOpenedAt = now
        self.dates = dates
    }

    var dates: TripDates {
        get {
            switch dateKind {
            case "days": .days(dayCount ?? 1)
            case "range":
                if let startDate, let endDate { .range(start: startDate, end: endDate) } else { .undecided }
            default: .undecided
            }
        }
        set {
            switch newValue {
            case .undecided:
                (dateKind, dayCount, startDate, endDate) = ("undecided", nil, nil, nil)
            case .days(let count):
                (dateKind, dayCount, startDate, endDate) = ("days", count, nil, nil)
            case .range(let start, let end):
                (dateKind, dayCount, startDate, endDate) = ("range", nil, start, end)
            }
        }
    }
}

/// A place the trip goes to. Chosen from candidates only; no free text (Notion 02 §1).
/// Large sights such as theme parks count too (agreed 2026-10-14, 「ディズニー旅行」).
struct Destination: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case prefecture, municipality, area, landmark
    }

    /// Municipality code for catalog entries, or a MapKit-derived key for areas and sights.
    var id: String
    var name: String
    /// Where it is, shown under the name (「京都府」, 「浦安市」).
    var context: String?
    var kind: Kind
    /// Kind of sight for landmarks (「テーマパーク」).
    var category: String?
    /// Filled for places found with MapKit. Catalog entries get a location when the map is built.
    var latitude: Double?
    var longitude: Double?

    /// The line under the name, kind first so places of different kinds can be told apart:
    /// 「市・京都府」「地域・東京都西多摩郡瑞穂町」「テーマパーク・浦安市」.
    static func detail(kind: Kind, name: String, context: String?, category: String?) -> String {
        let label = switch kind {
        case .prefecture: "都道府県"
        case .municipality: name.last.map { "市区町村".contains($0) ? String($0) : "市区町村" } ?? "市区町村"
        case .area: "地域"
        case .landmark: category ?? "観光地"
        }
        guard let context, !context.isEmpty else { return label }
        return "\(label)・\(context)"
    }

    var detail: String { Self.detail(kind: kind, name: name, context: context, category: category) }

    /// Name used in generated trip names: 「京都府」→「京都」, 「箱根町」→「箱根」.
    var shortName: String {
        switch kind {
        case .area, .landmark:
            return name
        case .prefecture:
            guard name != "北海道" else { return name }
            return String(name.dropLast())
        case .municipality:
            guard let last = name.last, "市町村".contains(last), name.count > 2 else { return name }
            return String(name.dropLast())
        }
    }
}

/// The three date stages (Notion 02 §3): undecided → day count → fixed dates.
enum TripDates: Hashable {
    case undecided
    case days(Int)
    case range(start: Date, end: Date)
}
