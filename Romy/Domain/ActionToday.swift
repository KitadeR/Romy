import Foundation

/// What the Action Home shows about today (Figma 「参考｜ActionのHome D 観光の時間」 71:288 and 26-01, Notion 02 §6-4
/// 2026-10-27): the plan that is 今, the plans left after it, and tonight's stay.
struct ActionToday {
    struct Row {
        let item: ItineraryItem
        let slot: DaySchedule.Slot
    }

    let day: Int
    /// The plan that is 今; nil when today has no plans or all are 済み.
    let now: Row?
    /// The plans after 今 that are not 済み, in order.
    let remaining: [Row]
    /// Tonight's stay, shown even when it is 今 or already 済み: the stay of tonight's night, also on a middle night of
    /// it (Notion 02 §6-5 決定 2026-10-28). Without one given, the last stay of the day.
    let stay: ItineraryItem?

    init(plans: [ItineraryItem], day: Int, schedule: DaySchedule, stay: ItineraryItem? = nil) {
        self.day = day
        let progress = DayProgress(
            plans: plans.map { DayProgress.Input(id: $0.id, isDone: $0.doneAt != nil) }, isToday: true
        )
        let rows = plans.compactMap { item in schedule.slot(for: item.id).map { Row(item: item, slot: $0) } }
        now = rows.first { progress.state(of: $0.item.id) == .now }
        remaining = rows.filter { progress.state(of: $0.item.id) == .upcoming }
        self.stay = stay ?? plans.last { $0.kind == .stay }
    }

    /// 「京都市東山区」→「東山区」: the big name is the ward, or the city when there is none (Notion 02 §6-4,
    /// 2026-10-08 「区・市の単位」).
    static func shortArea(_ area: String) -> String {
        guard area.hasSuffix("区"), let city = area.range(of: "市", options: .backwards) else { return area }
        let ward = area[city.upperBound...]
        return ward.isEmpty ? area : String(ward)
    }
}
