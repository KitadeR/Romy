import CoreLocation
import Foundation
import SwiftData

/// A place saved with ♥ in 「行きたい」 (Notion 02 §6-6: kept per trip, and kept after it is added to the itinerary).
@Model
final class WishPlace {
    var id: UUID
    var title: String
    var kindRaw: String
    /// Kind of place as Apple names it, in Japanese (「名所」「駅」「カフェ」).
    var category: String?
    /// Ward or city used to group the places (「京都市東山区」), looked up once after saving.
    var area: String?
    var latitude: Double
    var longitude: Double
    /// Apple's place identifier, kept to tell that the place is already in the itinerary.
    var placeID: String?
    var savedAt: Date
    var trip: Trip?

    init(
        title: String, kind: PlanKind, category: String?, area: String?,
        latitude: Double, longitude: Double, placeID: String?, now: Date = .now
    ) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.category = category
        self.area = area
        self.latitude = latitude
        self.longitude = longitude
        self.placeID = placeID
        self.savedAt = now
    }

    var kind: PlanKind { PlanKind(rawValue: kindRaw) ?? .other }

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    /// 「名所 ・ 京都市東山区」
    var detail: String {
        [category, area].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ・ ")
    }

    /// True when `item` is this place: the same Apple place, or the same name within 150 m.
    func isSamePlace(as item: ItineraryItem) -> Bool {
        if let placeID, let other = item.placeID { return placeID == other }
        guard item.title == title, let latitude = item.latitude, let longitude = item.longitude else { return false }
        return location.distance(from: CLLocation(latitude: latitude, longitude: longitude)) < 150
    }
}

/// What a wish was, to bring it back after 「元に戻す」.
struct WishSnapshot {
    let id: UUID
    let title: String
    let kindRaw: String
    let category: String?
    let area: String?
    let latitude: Double
    let longitude: Double
    let placeID: String?
    let savedAt: Date
}

extension WishPlace {
    func snapshot() -> WishSnapshot {
        WishSnapshot(
            id: id, title: title, kindRaw: kindRaw, category: category, area: area,
            latitude: latitude, longitude: longitude, placeID: placeID, savedAt: savedAt
        )
    }

    static func restored(from snapshot: WishSnapshot) -> WishPlace {
        let wish = WishPlace(
            title: snapshot.title, kind: PlanKind(rawValue: snapshot.kindRaw) ?? .other,
            category: snapshot.category, area: snapshot.area,
            latitude: snapshot.latitude, longitude: snapshot.longitude, placeID: snapshot.placeID,
            now: snapshot.savedAt
        )
        wish.id = snapshot.id
        wish.kindRaw = snapshot.kindRaw
        return wish
    }
}

extension Trip {
    /// The plan in the itinerary that is this wish, if it was added (Notion 02 §6-6 「追加済み」).
    func plan(for wish: WishPlace) -> ItineraryItem? {
        items.first { wish.isSamePlace(as: $0) }
    }

    /// A new plan from a wish, at the end of `day` (nil = 未定).
    func addPlan(from wish: WishPlace, toDay day: Int?) -> ItineraryItem {
        ItineraryItem(
            title: wish.title, day: day, order: nextOrder(on: day), kind: wish.kind,
            category: wish.category, area: wish.area, latitude: wish.latitude, longitude: wish.longitude,
            placeID: wish.placeID
        )
    }
}
