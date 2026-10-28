import Foundation

/// A snapshot of today's itinerary when the person asks. Searching and selecting never change these plans.
struct SceneRequest: Identifiable {
    let id: UUID
    let plans: [ItineraryItemSnapshot]
    let states: Set<ActionState>
    let strength: TiredStrength?
    /// When 今 started on the day's schedule; 「この内容で旅程に入れる」 ends it at the time of the search.
    var currentStartMinutes: Int?

    /// The plans between 今 and the first fixed plan ahead (not 済み), the stay among them, and that fixed plan.
    struct Ahead {
        let between: [ItineraryItemSnapshot]
        let stay: ItineraryItemSnapshot?
        let next: ItineraryItemSnapshot
    }

    enum Issue: Error, Equatable {
        case missingCurrent, needsLocation, needsFixedPlan, needsNextPlace, needsStayPlace, needsCheckIn

        var message: String {
            switch self {
            case .missingCurrent: "今の予定が変わりました。Homeから開き直してください。"
            case .needsLocation: "今いる場所が分かりません"
            case .needsFixedPlan: "この後の予定の時刻を決めてください"
            case .needsNextPlace: "次の固定の予定に場所を入れてください"
            case .needsStayPlace: "宿の予定に場所を入れてください"
            case .needsCheckIn: "宿のチェックインできる時刻を入れてください"
            }
        }
    }

    var current: ItineraryItemSnapshot? {
        plans.first { $0.id == id }
    }

    var currentPlace: ProposalPlace? {
        current.flatMap { Self.place($0) }
    }

    /// The first fixed plan ahead is the boundary, even when it has no location. Never skip it to fit a later one.
    func input(origin: ProposalPlace?, nowMinutes: Int) -> Result<SceneInput, Issue> {
        guard plans.contains(where: { $0.id == id }) else { return .failure(.missingCurrent) }
        guard let origin else { return .failure(.needsLocation) }
        guard let ahead = ahead(), let nextStart = ahead.next.fixedStartMinutes else {
            return .failure(.needsFixedPlan)
        }
        let next = ahead.next
        guard let nextPlace = Self.place(next) else { return .failure(.needsNextPlace) }
        var stay: SceneInput.Stay?
        if let hotel = ahead.stay {
            guard let place = Self.place(hotel) else { return .failure(.needsStayPlace) }
            guard let opens = hotel.notBeforeMinutes else { return .failure(.needsCheckIn) }
            stay = SceneInput.Stay(title: hotel.title, place: place, checkInMinutes: opens)
        }
        return .success(SceneInput(
            nowMinutes: nowMinutes, origin: origin, stay: stay, nextTitle: next.title, next: nextPlace,
            nextStartMinutes: nextStart, states: states,
            strength: states.contains(.tired) ? strength : nil
        ))
    }

    func ahead() -> Ahead? {
        guard let index = plans.firstIndex(where: { $0.id == id }) else { return nil }
        let remaining = Array(plans.dropFirst(index + 1).filter { $0.doneAt == nil })
        guard let nextIndex = remaining.firstIndex(where: { $0.fixedStartMinutes != nil }) else { return nil }
        let between = Array(remaining.prefix(nextIndex))
        return Ahead(
            between: between, stay: between.first { $0.kindRaw == PlanKind.stay.rawValue }, next: remaining[nextIndex]
        )
    }

    private static func place(_ item: ItineraryItemSnapshot) -> ProposalPlace? {
        guard let latitude = item.latitude, let longitude = item.longitude else { return nil }
        return ProposalPlace(name: item.title, latitude: latitude, longitude: longitude)
    }
}
