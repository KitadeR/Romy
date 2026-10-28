import Foundation

/// What 「この内容で旅程に入れる」 does to today's itinerary (Notion 02 §6-4 決定 2026-10-27・確定したあとの旅程と
/// 元に戻す, Figma 27). The way's plans go right after 今, 今 ends when the search was made, and the other plans
/// before the fixed one go to 未定. The stay and the fixed plan stay as they are. Nothing is marked 済み, and a
/// place whose luggage or seats were not checked is not written as checked.
struct SceneApply {
    struct NewPlan: Equatable {
        let title: String
        let kind: PlanKind
        let latitude: Double
        let longitude: Double
        let durationMinutes: Int
    }

    enum Problem: Error, Equatable {
        case changed, tooLate, doesNotFit

        var message: String {
            switch self {
            case .changed: "探したあとに旅程が変わりました。もう一度探してください。"
            case .tooLate: "探してから時間がたったので、もう一度探してください。"
            case .doesNotFit: "この案は次の予定に間に合わないので、旅程に入れられません。"
            }
        }
    }

    let day: Int
    let currentID: UUID
    let currentDurationMinutes: Int
    let added: [NewPlan]
    /// Plans before the fixed one that the way leaves out; they go to 未定 (見送る予定 in Figma 25-04).
    let skipped: [ItineraryItemSnapshot]
    /// The day as it was when searching.
    let basis: [ItineraryItemSnapshot]

    /// How long after the search its times are still put in as they are.
    static let freshMinutes = 10

    static func make(
        way: SceneWay, request: SceneRequest, searchedAtMinutes: Int, nowMinutes: Int
    ) -> Result<SceneApply, Problem> {
        guard way.fits else { return .failure(.doesNotFit) }
        guard nowMinutes - searchedAtMinutes <= freshMinutes else { return .failure(.tooLate) }
        guard let current = request.current, let day = current.day, let ahead = request.ahead() else {
            return .failure(.changed)
        }
        let duration = request.currentStartMinutes.map { max(5, searchedAtMinutes - $0) } ?? current.durationMinutes
        return .success(SceneApply(
            day: day,
            currentID: current.id,
            currentDurationMinutes: duration,
            added: way.steps.compactMap { newPlan($0) },
            skipped: ahead.between.filter { $0.id != ahead.stay?.id },
            basis: request.plans
        ))
    }

    /// True while today's plans are still the ones the search was made from.
    func matches(_ plans: [ItineraryItemSnapshot]) -> Bool {
        plans.map { Key($0) } == basis.map { Key($0) }
    }

    var message: String {
        let moved = skipped.isEmpty ? "" : "（\(skipped.count)件は未定へ）"
        return "\(added.count)件を旅程に追加しました\(moved)"
    }

    /// The check-in and the fixed plan are already in the itinerary; the other steps are new plans.
    private static func newPlan(_ step: SceneStep) -> NewPlan? {
        guard step.isAdded else { return nil }
        let kind: PlanKind = step.kind == .rest || step.kind == .eat ? .food : .other
        return NewPlan(
            title: step.planTitle, kind: kind,
            latitude: step.place.latitude, longitude: step.place.longitude,
            durationMinutes: max(5, step.leaveMinutes - step.startMinutes)
        )
    }

    private struct Key: Equatable {
        let id: UUID
        let day: Int?
        let order: Int
        let kindRaw: String
        let latitude: Double?
        let longitude: Double?
        let durationMinutes: Int
        let fixedStartMinutes: Int?
        let notBeforeMinutes: Int?
        let doneAt: Date?

        init(_ plan: ItineraryItemSnapshot) {
            id = plan.id; day = plan.day; order = plan.order; kindRaw = plan.kindRaw
            latitude = plan.latitude; longitude = plan.longitude; durationMinutes = plan.durationMinutes
            fixedStartMinutes = plan.fixedStartMinutes; notBeforeMinutes = plan.notBeforeMinutes; doneAt = plan.doneAt
        }
    }
}

extension SceneStep {
    /// The check-in and the fixed plan are already in the itinerary.
    var isAdded: Bool { kind != .checkIn && kind != .next }

    /// The title in the preview and of the plan put into the itinerary (Figma 25-04, 27).
    var planTitle: String {
        switch kind {
        case .dropLuggage, .lockerDrop: "\(title)に荷物を預ける"
        case .lockerPickUp: "\(title)で荷物を受け取る"
        case .rest: "\(title)で休む"
        case .eat: "\(title)で食べる"
        case .checkIn: "\(title)にチェックイン"
        case .next: title
        }
    }
}

/// Where a plan was before 「この内容で旅程に入れる」, so 「元に戻す」 can put it back.
struct PlanPosition: Equatable {
    let id: UUID
    let day: Int?
    let order: Int
    let durationMinutes: Int
}

extension Trip {
    /// Puts a confirmed way into the itinerary and returns the new plans and where the others were.
    /// The caller inserts the new plans into the model context.
    func apply(_ change: SceneApply) -> (added: [ItineraryItem], before: [PlanPosition]) {
        var list = items(on: change.day)
        let skippedIDs = Set(change.skipped.map(\.id))
        let touched = list + items.filter { skippedIDs.contains($0.id) && !list.contains($0) }
        let before = touched.map {
            PlanPosition(id: $0.id, day: $0.day, order: $0.order, durationMinutes: $0.durationMinutes)
        }
        var undecided = nextOrder(on: nil)
        for plan in list where skippedIDs.contains(plan.id) {
            plan.day = nil
            plan.order = undecided
            undecided += 1
        }
        list.removeAll { skippedIDs.contains($0.id) }
        let added = change.added.map { plan in
            let item = ItineraryItem(
                title: plan.title, day: change.day, order: 0, kind: plan.kind,
                latitude: plan.latitude, longitude: plan.longitude
            )
            item.durationMinutes = plan.durationMinutes
            item.travelMode = .walking
            return item
        }
        let afterNow = (list.firstIndex { $0.id == change.currentID }).map { $0 + 1 } ?? 0
        list.insert(contentsOf: added, at: afterNow)
        for (index, plan) in list.enumerated() { plan.order = index }
        list.first { $0.id == change.currentID }?.durationMinutes = change.currentDurationMinutes
        return (added, before)
    }

    /// 「元に戻す」 after a way was put in: the plans it moved or shortened go back. The caller deletes the new plans.
    func restore(_ before: [PlanPosition]) {
        for position in before {
            guard let plan = items.first(where: { $0.id == position.id }) else { continue }
            plan.day = position.day
            plan.order = position.order
            plan.durationMinutes = position.durationMinutes
        }
    }
}
