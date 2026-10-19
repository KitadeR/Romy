import CoreLocation
import Foundation

/// How 「行きたい」 is laid out (Notion 02 §6-6, 2026-10-14): Plan groups by ward, Action goes by distance.
enum WishList {
    struct Group: Identifiable {
        let title: String
        let wishes: [WishPlace]
        var id: String { title }
    }

    static let otherTitle = "そのほか"

    /// Places grouped by ward or city, in the order the groups were first saved; places without one go last.
    static func groups(_ wishes: [WishPlace]) -> [Group] {
        let ordered = wishes.sorted { $0.savedAt < $1.savedAt }
        var titles: [String] = []
        var members: [String: [WishPlace]] = [:]
        for wish in ordered {
            let title = wish.area.flatMap { $0.isEmpty ? nil : $0 } ?? otherTitle
            if members[title] == nil { titles.append(title) }
            members[title, default: []].append(wish)
        }
        let named = titles.filter { $0 != otherTitle } + titles.filter { $0 == otherTitle }
        return named.map { Group(title: $0, wishes: members[$0] ?? []) }
    }

    /// Nearest first, with the distance in meters.
    static func nearestFirst(_ wishes: [WishPlace], from origin: CLLocation) -> [(wish: WishPlace, meters: Double)] {
        wishes.map { ($0, $0.location.distance(from: origin)) }.sorted { $0.1 < $1.1 }
    }

    /// 「850m」「1.2km」「12km」
    static func distanceText(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10)m" }
        let kilometers = meters / 1000
        return kilometers < 10 ? String(format: "%.1fkm", kilometers) : "\(Int(kilometers.rounded()))km"
    }
}
