import Foundation

// The first scene of the question feature (Notion 02 §6-4, decided 2026-10-25): the person is tired, maybe with
// heavy luggage, before a stay that opens later (「15:00から」) and a fixed plan after it (17:00 予約).
// Behind 「Romyが案を作る」 (FigJam 229:1280): ①the time comes from the itinerary, ②places from the map,
// ③they are put into ways (at most two added places), ④the time is counted in code, ⑥the ways are put in order.
// ⑤checking facts (can the stay keep luggage before check-in) needs the AI and is not here: until it is, such a
// fact is 「？」 and the way is counted as if the luggage stays with the person.

/// What the scene is built from: now, the plans ahead in the itinerary, and the person's state.
struct SceneInput {
    struct Stay: Equatable {
        let title: String
        let place: ProposalPlace
        /// 「15:00から」; nil when check-in time is not known, which is taken as open now.
        let checkInMinutes: Int?
    }

    let nowMinutes: Int
    let origin: ProposalPlace
    /// The stay between now and the next fixed plan, when there is one.
    let stay: Stay?
    let nextTitle: String
    let next: ProposalPlace
    /// The next plan's start; it is not moved.
    let nextStartMinutes: Int
    let states: Set<ActionState>
    let strength: TiredStrength?

    var hasHeavyLuggage: Bool { states.contains(.heavyLuggage) }
}

/// One way through the time until the next plan, with every time counted in code.
struct SceneWay: Equatable {
    /// The headline that says why this way (Figma 25 3版: the reason is the title).
    enum Reason: Equatable {
        case dropFirst, dropIfAllowed, leastWalk, otherSeat, locker, stayNow

        var headline: String {
            switch self {
            case .dropFirst: "先に荷物を手放して、身軽に休む"
            case .dropIfAllowed: "預けられれば、身軽に休める"
            case .leastWalk: "歩くのは最小で、座ってゆっくり"
            case .otherSeat: "ほかの店で座って休む"
            case .locker: "宿に頼らず、駅で荷物を預ける"
            case .stayNow: "すぐ宿に入って休む"
            }
        }
    }

    let reason: Reason
    let steps: [SceneStep]
    let walkMinutes: Int
    /// Sitting at a rest or a meal, and in the room after check-in: an estimate, seats are not checked.
    let sitMinutes: Int
    /// Minutes between arriving at the next plan and its start; below zero when the way is late.
    let slackMinutes: Int
    /// Minutes the luggage is carried before it is let go, counted as if an unknown drop did not happen.
    /// Only used for the order, never shown (Notion 02 §6-4, 2026-10-22 ④).
    let carryMinutes: Int

    var fits: Bool { slackMinutes >= 0 }
    var shortfallMinutes: Int { max(0, -slackMinutes) }
    var hasUnknown: Bool { steps.contains { $0.isUnknown } }
    var addedPlaces: Int {
        Set(steps.filter { [.rest, .eat, .lockerDrop].contains($0.kind) }.map(\.place.name)).count
    }
}

/// One stop of a way, with its times.
struct SceneStep: Equatable {
    enum Kind: Equatable {
        case dropLuggage, rest, eat, checkIn, lockerDrop, lockerPickUp, next

        /// How long it takes at least; a rest, a meal and the room after check-in grow to fill the time.
        var minimumMinutes: Int {
            switch self {
            case .dropLuggage, .lockerDrop, .lockerPickUp: 5
            case .rest: 20
            case .eat: 40
            case .checkIn, .next: 0
            }
        }

        var isSeated: Bool { self == .rest || self == .eat || self == .checkIn }
    }

    let kind: Kind
    let title: String
    let place: ProposalPlace
    let walkBeforeMinutes: Int
    let arriveMinutes: Int
    /// When the step begins: later than arriving only when the stay is not open yet.
    let startMinutes: Int
    let leaveMinutes: Int
    /// The step rests on a fact that is not known (「？」): keeping luggage, a free locker.
    let isUnknown: Bool
}

enum ActionScene {
    static let waysShown = 3
    /// Under 「荷物が重い」, how a way that keeps luggage at the stay before check-in was checked (⑤).
    typealias LuggageCheck = (ProposalPlace) async -> CheckResult

    static let seatChip = ProposalChip(text: "座れる店", activity: .rest, query: "カフェ", category: "cafe")
    static let mealChip = ProposalChip(text: "座って食べられる店", activity: .eat, query: "レストラン", category: "restaurant")
    static let lockerChip = ProposalChip(text: "コインロッカー", query: "コインロッカー")

    static func build(
        _ input: SceneInput, search: @escaping CandidateSearch, walking: WalkingTime,
        luggageCheck: LuggageCheck = { _ in .unknown }
    ) async -> [SceneWay] {
        let available = input.nextStartMinutes - input.nowMinutes
        let usual = WalkLimit.oneWayMinutes(availableMinutes: available, walkLess: false)
        let oneWay = input.strength?.oneWayCapMinutes.map { min($0, usual) } ?? usual
        let radius = WalkLimit.meters(minutes: oneWay)
        let seat = input.states.contains(.hungry) ? mealChip : seatChip
        let seatKind: SceneStep.Kind = seat == mealChip ? .eat : .rest
        let nearHereOnly = input.strength?.restsNearHereOnly ?? false
        let maxAdded = input.strength?.maxAddedPlaces ?? 2

        let seatsHere = await ActionCandidates.gather(
            for: seat, near: input.origin, radiusMeters: radius, search: search
        ).places
        var plans: [(SceneWay.Reason, [Planned])] = []

        if let stay = input.stay, let checkIn = stay.checkInMinutes, checkIn > input.nowMinutes {
            let least = leastDetour(seatsHere, from: input.origin, to: stay.place)
            if input.hasHeavyLuggage {
                let context = Context(
                    input: input, stay: stay, seat: seat, seatKind: seatKind, seatsHere: seatsHere, least: least,
                    radius: radius, nearHereOnly: nearHereOnly, maxAdded: maxAdded, search: search
                )
                plans += await luggageWays(context, known: await luggageCheck(stay.place))
            }
            for (index, place) in ordered(seatsHere, least: least).enumerated() {
                plans.append((index == 0 ? .leastWalk : .otherSeat, [
                    Planned(seatKind, place.name, place), Planned(.checkIn, stay.title, stay.place)
                ]))
            }
        } else if let stay = input.stay {
            plans.append((.stayNow, [Planned(.checkIn, stay.title, stay.place)]))
        } else {
            let least = leastDetour(seatsHere, from: input.origin, to: input.next)
            for (index, place) in ordered(seatsHere, least: least).enumerated() {
                plans.append((index == 0 ? .leastWalk : .otherSeat, [Planned(seatKind, place.name, place)]))
            }
        }

        var ways: [SceneWay] = []
        for (reason, steps) in plans {
            let all = steps + [Planned(.next, input.nextTitle, input.next)]
            guard let way = await timed(reason, all, input: input, walking: walking), way.addedPlaces <= maxAdded
            else { continue }
            ways.append(way)
        }
        return Array(order(ways, heavyLuggage: input.hasHeavyLuggage).prefix(waysShown))
    }

    // MARK: - ③ Putting places into a way

    struct Context {
        let input: SceneInput
        let stay: SceneInput.Stay
        let seat: ProposalChip
        let seatKind: SceneStep.Kind
        let seatsHere: [ProposalPlace]
        let least: ProposalPlace?
        let radius: Double
        let nearHereOnly: Bool
        let maxAdded: Int
        let search: CandidateSearch
    }

    /// Under 「荷物が重い」: leave the luggage at the stay first (a 「？」 until the stay is known to keep it), or at
    /// a locker near here, whose free space is never known.
    private static func luggageWays(
        _ context: Context, known check: CheckResult
    ) async -> [(SceneWay.Reason, [Planned])] {
        let stay = context.stay
        let known = check == .official || check == .introduced
        var plans: [(SceneWay.Reason, [Planned])] = []
        let seatsNearStay = context.nearHereOnly ? [] : await ActionCandidates.gather(
            for: context.seat, near: stay.place, radiusMeters: context.radius, search: context.search
        ).places
        if let byStay = seatsNearStay.first(where: { $0.name != context.least?.name }) ?? seatsNearStay.first {
            plans.append((known ? .dropFirst : .dropIfAllowed, [
                Planned(.dropLuggage, stay.title, stay.place, unknown: !known),
                Planned(context.seatKind, byStay.name, byStay),
                Planned(.checkIn, stay.title, stay.place)
            ]))
        }
        guard context.maxAdded >= 2, !context.nearHereOnly else { return plans }
        let lockers = await ActionCandidates.gather(
            for: lockerChip, near: context.input.origin, radiusMeters: context.radius, search: context.search
        ).places
        if let locker = lockers.first,
           let byLocker = context.seatsHere.min(by: { locker.meters(to: $0) < locker.meters(to: $1) }) {
            plans.append((.locker, [
                Planned(.lockerDrop, locker.name, locker, unknown: true),
                Planned(context.seatKind, byLocker.name, byLocker),
                Planned(.lockerPickUp, locker.name, locker),
                Planned(.checkIn, stay.title, stay.place)
            ]))
        }
        return plans
    }

    struct Planned {
        let kind: SceneStep.Kind
        let title: String
        let place: ProposalPlace
        let unknown: Bool

        init(_ kind: SceneStep.Kind, _ title: String, _ place: ProposalPlace, unknown: Bool = false) {
            self.kind = kind
            self.title = title
            self.place = place
            self.unknown = unknown
        }
    }

    /// The seat that adds the least straight-line distance on the way to `target`.
    private static func leastDetour(
        _ places: [ProposalPlace], from origin: ProposalPlace, to target: ProposalPlace
    ) -> ProposalPlace? {
        places.prefix(10).min {
            origin.meters(to: $0) + $0.meters(to: target) < origin.meters(to: $1) + $1.meters(to: target)
        }
    }

    /// The least-detour seat first, then the nearest others, for 「ほかの店」.
    private static func ordered(_ places: [ProposalPlace], least: ProposalPlace?) -> [ProposalPlace] {
        guard let least else { return [] }
        return [least] + places.filter { $0.name != least.name }.prefix(1)
    }

    // MARK: - ④ Counting the time

    /// The times of a way. A rest or meal before check-in grows until the stay opens; the room after check-in,
    /// or the last rest when there is no stay, grows until it is time to leave for the next plan
    /// (`ActionGap.marginMinutes` before it). Nil when a walk has no answer.
    static func timed(
        _ reason: SceneWay.Reason, _ planned: [Planned], input: SceneInput, walking: WalkingTime
    ) async -> SceneWay? {
        var walks: [Int] = []
        var from = input.origin
        for step in planned {
            guard let minutes = await walking(from, step.place) else { return nil }
            walks.append(minutes)
            from = step.place
        }
        let deadline = input.nextStartMinutes - ActionGap.marginMinutes
        let checkInIndex = planned.firstIndex { $0.kind == .checkIn }
        var stays = planned.map(\.kind.minimumMinutes)

        // Before check-in (or before the next plan when there is no stay), the last seat takes the spare time.
        let split = checkInIndex ?? planned.count - 1
        let firstPart = (0...split).reduce(input.nowMinutes) { time, index in
            time + walks[index] + (index < split ? stays[index] : 0)
        }
        let opens = checkInIndex.flatMap { _ in input.stay?.checkInMinutes } ?? input.nowMinutes
        let target = checkInIndex == nil ? deadline : max(firstPart, opens)
        if let seat = (0..<split).last(where: { planned[$0].kind.isSeated }) {
            stays[seat] += max(0, target - firstPart)
        }

        // After check-in, the room takes what is left before leaving for the next plan.
        if let checkInIndex {
            let start = max(firstPart, opens)
            let after = (checkInIndex + 1..<planned.count).reduce(0) { sum, index in
                sum + walks[index] + (index < planned.count - 1 ? stays[index] : 0)
            }
            stays[checkInIndex] = max(0, deadline - after - start)
        }

        var time = input.nowMinutes
        var steps: [SceneStep] = []
        for (index, step) in planned.enumerated() {
            time += walks[index]
            let arrive = time
            if step.kind == .checkIn { time = max(time, opens) }
            let start = time
            time += step.kind == .next ? 0 : stays[index]
            steps.append(SceneStep(
                kind: step.kind, title: step.title, place: step.place, walkBeforeMinutes: walks[index],
                arriveMinutes: arrive, startMinutes: start, leaveMinutes: time, isUnknown: step.unknown
            ))
        }
        let arrival = steps.last?.arriveMinutes ?? input.nowMinutes
        let sit = steps.filter(\.kind.isSeated).reduce(0) { $0 + $1.leaveMinutes - $1.startMinutes }
        return SceneWay(
            reason: reason, steps: steps, walkMinutes: walks.reduce(0, +), sitMinutes: sit,
            slackMinutes: input.nextStartMinutes - arrival,
            carryMinutes: carryUntil(steps) - input.nowMinutes
        )
    }

    /// When the luggage is let go: at a known drop; otherwise it is counted as kept until check-in, or until the
    /// next plan when there is no stay.
    private static func carryUntil(_ steps: [SceneStep]) -> Int {
        if let drop = steps.first(where: { [.dropLuggage, .lockerDrop].contains($0.kind) && !$0.isUnknown }) {
            return drop.arriveMinutes
        }
        return (steps.first { $0.kind == .checkIn } ?? steps.last)?.startMinutes ?? 0
    }

    // MARK: - ⑥ Putting the ways in order

    /// Ways that fit first. With heavy luggage, the one that lets it go soonest; otherwise, the longest sit and
    /// then the least walk. A way resting on 「？」 is never first while a way without one is there.
    static func order(_ ways: [SceneWay], heavyLuggage: Bool) -> [SceneWay] {
        let sorted = ways.sorted { lhs, rhs in
            if lhs.fits != rhs.fits { return lhs.fits }
            if !lhs.fits { return lhs.shortfallMinutes < rhs.shortfallMinutes }
            if heavyLuggage, lhs.carryMinutes != rhs.carryMinutes { return lhs.carryMinutes < rhs.carryMinutes }
            if lhs.sitMinutes != rhs.sitMinutes { return lhs.sitMinutes > rhs.sitMinutes }
            return lhs.walkMinutes < rhs.walkMinutes
        }
        guard let first = sorted.first, first.hasUnknown,
              let known = sorted.firstIndex(where: { !$0.hasUnknown && $0.fits == first.fits })
        else { return sorted }
        var result = sorted
        result.insert(result.remove(at: known), at: 0)
        return result
    }
}
