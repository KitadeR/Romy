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
    /// How long the plan takes, in minutes (Notion 02 §6-5 時刻のシート 「長さ」).
    var durationMinutes: Int = 60
    /// Start fixed by the person (鍵), in minutes after midnight; nil while the start is a guess (目安).
    var fixedStartMinutes: Int?
    /// The earliest the plan can start, in minutes after midnight (a stay's check-in 「15:00から」); nil when any
    /// time is fine. Unlike a fixed start the plan may start later; a guess that comes earlier waits until then
    /// (Notion 02 §6-4, 2026-10-22: 「この時刻より前は不可」 is its own kind, apart from a fixed time).
    var notBeforeMinutes: Int?
    /// When the person marked the plan 済み (Notion 02 §6-5 「済みを付ける・外す」); nil while it is not done.
    /// 今 and スキップ are not stored; they come from the order of the plans (`DayProgress`).
    var doneAt: Date?
    /// Whether the plan needs booking (Notion 02 §6-3, 2026-10-27 「予約：まだ」を出す予定): nil until asked.
    /// A stay needs it without being asked (`needsBooking`).
    var bookingNeeded: Bool?
    /// When the person marked the booking done (「予約完了にする」); nil while it is not booked.
    var bookedAt: Date?
    /// How the person goes from the plan before to this one, when they chose it (Notion 02 §6-5 ②移動の行);
    /// nil means the first guess (`TravelMode.defaultMode`).
    var travelModeRaw: String?
    /// Photo the person chose for the plan (shown on its card and at the top of its detail); nil until chosen.
    @Attribute(.externalStorage) var photo: Data?
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

    var travelMode: TravelMode? {
        get { travelModeRaw.flatMap(TravelMode.init(rawValue:)) }
        set { travelModeRaw = newValue?.rawValue }
    }

    /// Listed in 準備 with 「予約：まだ／済み」: a stay always, any other plan once the person said it needs booking.
    var needsBooking: Bool { kind == .stay || bookingNeeded == true }
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

extension Trip {
    /// Moves a plan to the end of another day, or of 未定 when `day` is nil (Notion 02 §6-3 「予定を動かす」).
    func move(_ item: ItineraryItem, toDay day: Int?) {
        let from = items(on: ItineraryDays.placement(of: item.day, dayCount: ItineraryDays.count(of: dates)))
        guard !(item.day == day && from.contains { $0.id == item.id }) else { return }
        item.day = day
        item.order = nextOrder(on: day)
        renumber(day: day)
    }

    /// Drops a plan onto another plan: it takes that plan's place, in that plan's day (the plans between shift by one).
    func reorder(_ item: ItineraryItem, onto target: ItineraryItem) {
        guard item.id != target.id else { return }
        let dayCount = ItineraryDays.count(of: dates)
        let targetDay = ItineraryDays.placement(of: target.day, dayCount: dayCount)
        var list = items(on: targetDay)
        guard let targetIndex = list.firstIndex(where: { $0.id == target.id }) else { return }
        let oldDay = ItineraryDays.placement(of: item.day, dayCount: dayCount)
        list.removeAll { $0.id == item.id }
        list.insert(item, at: min(targetIndex, list.count))
        item.day = targetDay
        for (index, plan) in list.enumerated() { plan.order = index }
        if oldDay != targetDay { renumber(day: oldDay) }
    }

    /// Closes gaps in the order of a day (or of 未定).
    func renumber(day: Int?) {
        for (index, plan) in items(on: day).enumerated() { plan.order = index }
    }
}

/// What a plan was, to bring it back after 「予定を削除」 and 「元に戻す」 (Notion 02 §6-6 削除の取り消し).
/// The plan itself is deleted, so this keeps every stored value.
struct ItineraryItemSnapshot {
    let id: UUID
    let title: String
    let day: Int?
    let order: Int
    let kindRaw: String
    let category: String?
    let area: String?
    let latitude: Double?
    let longitude: Double?
    let placeID: String?
    let createdAt: Date
    let durationMinutes: Int
    let fixedStartMinutes: Int?
    let notBeforeMinutes: Int?
    let doneAt: Date?
    let travelModeRaw: String?
    let photo: Data?
    var bookingNeeded: Bool?
    var bookedAt: Date?
}

extension ItineraryItem {
    func snapshot() -> ItineraryItemSnapshot {
        ItineraryItemSnapshot(
            id: id, title: title, day: day, order: order, kindRaw: kindRaw, category: category, area: area,
            latitude: latitude, longitude: longitude, placeID: placeID, createdAt: createdAt,
            durationMinutes: durationMinutes, fixedStartMinutes: fixedStartMinutes,
            notBeforeMinutes: notBeforeMinutes, doneAt: doneAt,
            travelModeRaw: travelModeRaw, photo: photo, bookingNeeded: bookingNeeded, bookedAt: bookedAt
        )
    }

    /// A plan with the same values (and the same place in its day, since the order is kept).
    static func restored(from snapshot: ItineraryItemSnapshot) -> ItineraryItem {
        let item = ItineraryItem(
            title: snapshot.title, day: snapshot.day, order: snapshot.order,
            kind: PlanKind(rawValue: snapshot.kindRaw) ?? .other, category: snapshot.category, area: snapshot.area,
            latitude: snapshot.latitude, longitude: snapshot.longitude, placeID: snapshot.placeID,
            now: snapshot.createdAt
        )
        item.id = snapshot.id
        item.kindRaw = snapshot.kindRaw
        item.durationMinutes = snapshot.durationMinutes
        item.fixedStartMinutes = snapshot.fixedStartMinutes
        item.notBeforeMinutes = snapshot.notBeforeMinutes
        item.doneAt = snapshot.doneAt
        item.travelModeRaw = snapshot.travelModeRaw
        item.photo = snapshot.photo
        item.bookingNeeded = snapshot.bookingNeeded
        item.bookedAt = snapshot.bookedAt
        return item
    }
}

extension Trip {
    /// The plan a route to `item` starts from (Notion 02 §6-6 4回目): the plan before it in its day when the trip is
    /// not in Action. Nil means where the person is: in Action, for the first plan of a day, for 未定,
    /// and when the plan before has no place.
    func routeOrigin(for item: ItineraryItem, isAction: Bool) -> ItineraryItem? {
        guard !isAction else { return nil }
        let dayCount = ItineraryDays.count(of: dates)
        guard let day = ItineraryDays.placement(of: item.day, dayCount: dayCount) else { return nil }
        let plans = items(on: day)
        guard let index = plans.firstIndex(where: { $0.id == item.id }), index > 0 else { return nil }
        let before = plans[index - 1]
        return before.latitude != nil && before.longitude != nil ? before : nil
    }
}
