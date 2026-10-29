import Foundation

/// A snapshot of today's itinerary when the person asks. Searching and selecting never change these plans.
struct SceneRequest: Identifiable {
    let id: UUID
    let plans: [ItineraryItemSnapshot]
    let states: Set<ActionState>
    let strength: TiredStrength?
    /// When 今 started on the day's schedule; 「この内容で旅程に入れる」 ends it at the time of the search.
    var currentStartMinutes: Int?

    /// The plans 今 may leave out, the stay among the plans ahead, and the fixed plan that ends the time.
    struct Ahead {
        /// Plans before the end that a way leaves out (they go to 未定); none when a chosen length ends the time.
        let between: [ItineraryItemSnapshot]
        let stay: ItineraryItemSnapshot?
        /// The first fixed plan ahead; nil when there is none and the stay's check-in or a chosen length ends it.
        let next: ItineraryItemSnapshot?
    }

    enum Issue: Error, Equatable {
        case missingCurrent, needsLocation

        var message: String {
            switch self {
            case .missingCurrent: "今の予定が変わりました。Homeから開き直してください。"
            case .needsLocation: "今いる場所が分かりません"
            }
        }
    }

    var current: ItineraryItemSnapshot? {
        plans.first { $0.id == id }
    }

    var currentPlace: ProposalPlace? {
        current.flatMap { Self.place($0) }
    }

    /// What ends the time (2026-10-29, るわさん「どんな状態でも案がみれるようにする」): the first fixed plan ahead,
    /// even without a place (never skipped to fit a later one); otherwise the stay's check-in when it is known and
    /// still ahead; otherwise the length the person chose. A time is never guessed.
    func input(origin: ProposalPlace?, nowMinutes: Int, chosenMinutes: Int) -> Result<SceneInput, Issue> {
        guard plans.contains(where: { $0.id == id }), let ahead = ahead(nowMinutes: nowMinutes) else {
            return .failure(.missingCurrent)
        }
        guard let origin else { return .failure(.needsLocation) }
        // A stay without a place or a check-in time cannot be planned around, so it is left as it is.
        let stay = ahead.stay.flatMap { hotel -> SceneInput.Stay? in
            guard let place = Self.place(hotel), let opens = hotel.notBeforeMinutes else { return nil }
            return SceneInput.Stay(title: hotel.title, place: place, checkInMinutes: opens)
        }
        let end: SceneInput.End
        let endMinutes: Int
        if let next = ahead.next, let start = next.fixedStartMinutes {
            end = .plan(title: next.title, place: Self.place(next))
            endMinutes = start
        } else if let opens = stay?.checkInMinutes, opens > nowMinutes {
            end = .checkIn
            endMinutes = opens
        } else {
            end = .chosen
            endMinutes = nowMinutes + chosenMinutes
        }
        return .success(SceneInput(
            nowMinutes: nowMinutes, origin: origin, stay: stay, end: end, endMinutes: endMinutes, states: states,
            strength: states.contains(.tired) ? strength : nil
        ))
    }

    func ahead(nowMinutes: Int) -> Ahead? {
        guard let index = plans.firstIndex(where: { $0.id == id }) else { return nil }
        let remaining = Array(plans.dropFirst(index + 1).filter { $0.doneAt == nil })
        let isStay: (ItineraryItemSnapshot) -> Bool = { $0.kindRaw == PlanKind.stay.rawValue }
        if let nextIndex = remaining.firstIndex(where: { $0.fixedStartMinutes != nil }) {
            let between = Array(remaining.prefix(nextIndex))
            return Ahead(between: between, stay: between.first(where: isStay), next: remaining[nextIndex])
        }
        if let stayIndex = remaining.firstIndex(where: { plan in
            isStay(plan) && Self.place(plan) != nil && (plan.notBeforeMinutes ?? .min) > nowMinutes
        }) {
            return Ahead(between: Array(remaining.prefix(stayIndex)), stay: remaining[stayIndex], next: nil)
        }
        // A chosen length: nothing is left out, and a stay already open can still be entered.
        let open = remaining.first { plan in
            isStay(plan) && Self.place(plan) != nil && plan.notBeforeMinutes.map { $0 <= nowMinutes } == true
        }
        return Ahead(between: [], stay: open, next: nil)
    }

    private static func place(_ item: ItineraryItemSnapshot) -> ProposalPlace? {
        guard let latitude = item.latitude, let longitude = item.longitude else { return nil }
        return ProposalPlace(name: item.title, latitude: latitude, longitude: longitude)
    }
}
