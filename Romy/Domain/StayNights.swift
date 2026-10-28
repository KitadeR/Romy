import Foundation

/// What kind of stay it is (Notion 02 §6-3 2026-10-13 「どこに泊まる？」, §6-5 決定 2026-10-28 宿の種類).
/// It changes only the booking mark and what is asked: a friend's house needs no booking, and a stay decided later
/// has no place yet.
enum StayKind: String, CaseIterable, Identifiable {
    case hotel, rental, friend, later

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hotel: "ホテル"
        case .rental: "Airbnb・民泊"
        case .friend: "友達の家"
        case .later: "あとで決める"
        }
    }

    /// The line under the label in 「どこに泊まる？」 (Figma 15-7).
    var detail: String {
        switch self {
        case .hotel: "名前で探す"
        case .rental: "住所を入れる"
        case .friend: "名前と住所だけ"
        case .later: "「宿」だけ旅程に置く"
        }
    }
}

extension ItineraryItem {
    var stayKind: StayKind {
        get { stayKindRaw.flatMap(StayKind.init(rawValue:)) ?? .hotel }
        set { stayKindRaw = newValue.rawValue }
    }

    /// A stay's nights; at least one.
    var nights: Int {
        get { max(nightsCount ?? 1, 1) }
        set { nightsCount = max(newValue, 1) }
    }

    /// Whether the stay is where the person sleeps on the night of `day`.
    func isStaying(onNightOf day: Int) -> Bool {
        guard kind == .stay, let first = self.day else { return false }
        return day >= first && day < first + nights
    }

    /// The day the stay is left: the day after its last night.
    var leavingDay: Int? { day.map { $0 + nights } }

    /// 「最終22:00を過ぎそう」: the guessed arrival is later than the last check-in (Notion 02 §6-5 決定 2026-10-28
    /// 最終チェックイン). The first of the 「間に合うかの警告」.
    func arrivesTooLate(at minutes: Int) -> Bool {
        guard kind == .stay, let last = lastCheckInMinutes else { return false }
        return minutes > last
    }
}

/// The lines a stay adds to the other days of its nights (Notion 02 §6-5 決定 2026-10-28 何泊の持ち方, 合意 2026-10-10):
/// 「ホテル名 ・ 2泊目」 at the end of a middle day, and 「ホテルを出る ・ 11:00までにチェックアウト」 first on the day
/// it is left. They are not stored; they come from the stay, cannot be moved or deleted, and open the stay.
struct StayLine: Identifiable, Equatable {
    enum Kind: Equatable {
        case leaving
        /// The night's number: 2 for 「2泊目」.
        case night(Int)
    }

    let kind: Kind
    let stay: ItineraryItem

    var id: String {
        switch kind {
        case .leaving: "leaving-\(stay.id)"
        case .night(let number): "night\(number)-\(stay.id)"
        }
    }

    /// 「2泊目」, or 「11:00までにチェックアウト」 when the time is known.
    var note: String? {
        switch kind {
        case .night(let number): "\(number)泊目"
        case .leaving: stay.checkOutMinutes.map { "\(DaySchedule.clock($0))までにチェックアウト" }
        }
    }

    static func == (lhs: StayLine, rhs: StayLine) -> Bool { lhs.kind == rhs.kind && lhs.stay.id == rhs.stay.id }
}

enum StayNights {
    /// The most nights a stay from `day` can have: up to the end of the trip, at least one
    /// (Notion 02 §6-5 決定 2026-10-28 日数を超える泊数). A stay in 未定 or on a trip without days has no limit.
    static func maxNights(from day: Int?, dayCount: Int) -> Int? {
        guard dayCount > 0, let day else { return nil }
        return max(dayCount - day, 1)
    }
}

extension Trip {
    private var placedStays: [ItineraryItem] {
        let dayCount = ItineraryDays.count(of: dates)
        return items
            .filter { $0.kind == .stay && ItineraryDays.placement(of: $0.day, dayCount: dayCount) != nil }
            .sorted { ($0.day ?? 0, $0.order) < ($1.day ?? 0, $1.order) }
    }

    /// The stays left on `day`, to show first, and the stays whose middle night `day` is, to show last.
    /// Lines past the end of the trip are not shown; the stay keeps its nights.
    func stayLines(on day: Int) -> (leaving: [StayLine], nights: [StayLine]) {
        let stays = placedStays
        let leaving = stays.filter { $0.leavingDay == day }.map { StayLine(kind: .leaving, stay: $0) }
        let nights = stays.compactMap { stay -> StayLine? in
            guard let first = stay.day, day > first, stay.isStaying(onNightOf: day) else { return nil }
            return StayLine(kind: .night(day - first + 1), stay: stay)
        }
        return (leaving, nights)
    }

    func hasStayLines(on day: Int) -> Bool {
        let lines = stayLines(on: day)
        return !lines.leaving.isEmpty || !lines.nights.isEmpty
    }

    /// Where the person sleeps on the night of `day` (Notion 02 §6-5 決定 2026-10-28): the stay of that night, and on
    /// a day of moving the next one.
    func stayTonight(on day: Int) -> ItineraryItem? {
        placedStays.last { $0.isStaying(onNightOf: day) }
    }
}
