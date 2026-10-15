import Foundation
import SwiftData

/// One plan in a trip's itinerary (Notion 02 §5, §6-5). It can be just a name, or a place found with Apple's search.
/// A plan sits on a day of the trip, or in 未定 while its day is not decided.
@Model
final class ItineraryItem {
    var id: UUID
    var title: String
    /// 1-based day of the trip; nil while it sits in 未定.
    /// Kept as a day number, so a day-count trip that gets dates keeps its plans on the same days (Notion 02 §5).
    var day: Int?
    /// Position inside its day (or inside 未定).
    var order: Int
    var kindRaw: String
    /// Kind of place as Apple names it, in Japanese (「寺」ではなく「名所」「駅」「カフェ」).
    var category: String?
    /// Ward or city used to group places (「京都市東山区」). Looked up once when the place is saved (Notion 05, 2026-10-14).
    var area: String?
    var latitude: Double?
    var longitude: Double?
    /// Apple's place identifier, kept for the place card later (iOS 18+).
    var placeID: String?
    var createdAt: Date
    var trip: Trip?

    init(
        title: String,
        day: Int?,
        order: Int,
        kind: PlanKind,
        category: String? = nil,
        area: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        placeID: String? = nil,
        now: Date = .now
    ) {
        self.id = UUID()
        self.title = title
        self.day = day
        self.order = order
        self.kindRaw = kind.rawValue
        self.category = category
        self.area = area
        self.latitude = latitude
        self.longitude = longitude
        self.placeID = placeID
        self.createdAt = now
    }

    var kind: PlanKind {
        get { PlanKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}

/// The broad kind shown as the small label on a card (「観光」「食事」).
enum PlanKind: String, CaseIterable {
    case sight, food, shopping, stay, transport, other
    /// Added by name only, without a place.
    case nameOnly

    /// Card label; a plan added by name only has none.
    var label: String? {
        switch self {
        case .sight: "観光"
        case .food: "食事"
        case .shopping: "買い物"
        case .stay: "宿"
        case .transport: "交通"
        case .other: "その他"
        case .nameOnly: nil
        }
    }

    var symbol: String {
        switch self {
        case .sight: "camera"
        case .food: "fork.knife"
        case .shopping: "bag"
        case .stay: "bed.double"
        case .transport: "tram"
        case .other: "mappin"
        case .nameOnly: "textformat"
        }
    }
}

extension Trip {
    /// Plans of one day, or of 未定 when `day` is nil, in their order.
    /// Plans whose day is past the end of the trip are shown in 未定, so nothing is lost.
    func items(on day: Int?) -> [ItineraryItem] {
        let days = ItineraryDays.count(of: dates)
        return items
            .filter { ItineraryDays.placement(of: $0.day, dayCount: days) == day }
            .sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
    }

    /// Order for a plan added at the end of a day (or of 未定).
    func nextOrder(on day: Int?) -> Int {
        (items(on: day).map(\.order).max() ?? -1) + 1
    }

    /// After the dates change, plans past the last day move to 未定 instead of disappearing (Notion 02 §3).
    func moveItemsPastLastDay() {
        let days = ItineraryDays.count(of: dates)
        var next = nextOrder(on: nil)
        for item in items.sorted(by: { ($0.day ?? 0, $0.order) < ($1.day ?? 0, $1.order) }) {
            guard let day = item.day, day > days else { continue }
            item.day = nil
            item.order = next
            next += 1
        }
    }
}
