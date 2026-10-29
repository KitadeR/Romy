import Foundation

/// What the relay found about leaving luggage at a stay before check-in (Notion 02 §6-4「決定（2026-10-29）｜
/// 事実の確認⑤」, 04「2026-10-28｜Romy Now｜荷物預かりの情報確認」). Kept on the stay so Romy Now does not wait.
nonisolated struct LuggageFact: Codable, Equatable {
    struct Source: Codable, Equatable {
        let url: String
        let title: String?
        let official: Bool
    }

    /// 「official」「introduced」「unknown」「contradicted」, as the relay says.
    let status: String
    /// Conditions as the source writes them (「当日の朝から」); only with a yes.
    let conditions: [String]
    let sources: [Source]
    /// The stay's own lockers, apart from the front desk: 「yes」「no」「unknown」.
    let locker: String
    let foundName: String?
    /// When Romy checked; a shared result keeps its own date (「10/20に確認」).
    let checkedAt: Date
    /// The stay it was checked for, so a stay whose place changed is checked again.
    /// The relay does not send it; Romy sets it before keeping the check.
    var placeKey: String?

    var result: CheckResult {
        switch status {
        case "official": .official
        case "introduced": .introduced
        case "contradicted": .contradicted
        default: .unknown
        }
    }

    var hasLocker: Bool { locker == "yes" }

    /// ✓・✗ are used for 30 days, 紹介 and ？ for 3, as on the relay (Notion 04「2026-10-28｜結果の保存」).
    func isFresh(at now: Date) -> Bool {
        let days: Double = (status == "official" || status == "contradicted") ? 30 : 3
        return now.timeIntervalSince(checkedAt) < days * 86_400
    }

    /// The place as Romy knows it: the MapKit place ID, or the name and the town.
    static func placeKey(title: String, placeID: String?, area: String?) -> String {
        placeID.map { "id:\($0)" } ?? "na:\(title)|\(area ?? "")"
    }
}

/// How one way of Romy Now stands on the luggage check (Figma 23 2版).
enum LuggageMark: Equatable {
    /// The way does not leave luggage at the stay.
    case none
    /// 「宿で預けられるか確認中…」: the answer is still coming.
    case checking
    case checked(LuggageFact)
}

extension LuggageFact {
    /// One line under a way (Figma 23 2版 01〜03, 02 §6-4「宿のロッカー」).
    var caption: String {
        switch result {
        case .official: "✓ チェックイン前も預けられる（公式）"
        case .introduced: "チェックイン前に預けられると紹介されています"
        case .contradicted: "✗ この宿はチェックイン前の預かりがありません"
        case .unknown: hasLocker ? "宿のロッカーあり（空きは分かりません）" : "？ 宿で預けられるかは未確認です"
        }
    }

    /// 「10/28 確認」
    func checkedDateText(calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: checkedAt)
        return "\(parts.month ?? 0)/\(parts.day ?? 0) 確認"
    }
}

/// Which stays to check ahead of time: the day before and the day of check-in, with a place, kept by
/// someone (a hotel or an Airbnb・民泊), and not checked recently (Notion 02 §6-4「いつ調べるか」).
enum LuggagePrefetch {
    struct Stay: Equatable {
        let id: UUID
        let title: String
        let placeID: String?
        let area: String?
        let latitude: Double?
        let checkInDate: Date?
        let stayKind: StayKind?
        let fact: LuggageFact?
    }

    static func due(_ stays: [Stay], now: Date, calendar: Calendar = .current) -> [Stay] {
        let today = calendar.startOfDay(for: now)
        return stays.filter { stay in
            guard stay.latitude != nil, stay.stayKind == .hotel || stay.stayKind == .rental,
                  let date = stay.checkInDate else { return false }
            let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? -1
            guard days == 0 || days == 1 else { return false }
            let key = LuggageFact.placeKey(title: stay.title, placeID: stay.placeID, area: stay.area)
            guard let fact = stay.fact, fact.placeKey == key else { return true }
            return !fact.isFresh(at: now)
        }
    }
}
