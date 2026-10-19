import Foundation

/// A search on the map for one chip. The map itself is behind `CandidateSearch`, so this can be tested.
struct CandidateQuery: Equatable {
    let text: String
    /// Only places of this kind of ours (`ActionCandidates.categoryWords`); nil for any place.
    let category: String?
    let center: ProposalPlace
    let spanDegrees: Double
}

/// Runs one search; the places in any order.
typealias CandidateSearch = (CandidateQuery) async -> [ProposalPlace]

/// Walking minutes between two places; nil when there is no answer.
typealias WalkingTime = (ProposalPlace, ProposalPlace) async -> Int?

enum ActionCandidates {
    /// The word for each kind of place, searched alone when the chip's own words find nothing
    /// (02 §6-4, 2026-10-19: 0 hits → retry with the category word).
    static let categoryWords = [
        "bakery": "パン屋", "cafe": "カフェ", "restaurant": "レストラン", "convenience": "コンビニ",
        "park": "公園", "beach": "海岸"
    ]

    /// Places for a chip within the walking limit, nearest first. The kind of place is asked for first; when
    /// that finds nothing the words are searched for any place; when that finds nothing too, the category word
    /// is searched alone (`retriedWith`).
    static func gather(
        for chip: ProposalChip, near origin: ProposalPlace, radiusMeters: Double, search: CandidateSearch
    ) async -> (places: [ProposalPlace], retriedWith: String?) {
        let span = WalkLimit.spanDegrees(radiusMeters: radiusMeters)
        let category = categoryWords[chip.category] != nil ? chip.category : nil

        func run(_ text: String, _ category: String?) async -> [ProposalPlace] {
            let found = await search(CandidateQuery(text: text, category: category, center: origin, spanDegrees: span))
            return found.filter { origin.meters(to: $0) <= radiusMeters }
                .sorted { origin.meters(to: $0) < origin.meters(to: $1) }
        }

        if let category {
            let found = await run(chip.query, category)
            if !found.isEmpty { return (found, nil) }
        }
        let found = await run(chip.query, nil)
        if !found.isEmpty { return (found, nil) }
        guard let category, let word = categoryWords[category], word != chip.query else { return ([], nil) }
        return (await run(word, category), word)
    }
}

/// One way through the places to the next plan, with the time it takes counted in code, not by a model.
struct ActionCombination: Equatable {
    struct Stop: Equatable {
        let chip: ProposalChip
        let place: ProposalPlace
    }

    let stops: [Stop]
    /// Walking from where the person is, through the stops, to the next plan.
    let walkMinutes: Int
    /// Walking from where the person is straight to the next plan, which is needed anyway.
    /// `walkMinutes - directWalkMinutes` is the walk the detour adds (whether that is what the limit should
    /// measure is not decided: 02 §6-4, open issue a).
    let directWalkMinutes: Int?
    let stayMinutes: Int
    let availableMinutes: Int
    /// A walk between two of the points had no answer, so the total is not known.
    let missingWalk: Bool

    var totalMinutes: Int { walkMinutes + stayMinutes + ActionGap.marginMinutes }
    var slackMinutes: Int { availableMinutes - totalMinutes }
    var fits: Bool { !missingWalk && slackMinutes >= 0 }
    /// 「○分足りない」; zero when it fits or the time is not known.
    var shortfallMinutes: Int { missingWalk ? 0 : max(0, -slackMinutes) }
    var detourWalkMinutes: Int? { directWalkMinutes.map { max(0, walkMinutes - $0) } }
}

struct ActionProposalOutcome: Equatable {
    /// Up to three ways, the one with the most time to spare first. Ways that do not fit are kept, with how
    /// many minutes they are short, so the person sees why.
    let combinations: [ActionCombination]
    /// Chips whose search found nothing; the rest are still proposed.
    let chipsWithoutPlaces: [ProposalChip]
    /// The words each chip was searched with when its own words found nothing.
    let retriedWith: [String: String]

    var isEmpty: Bool { combinations.isEmpty }
}

enum ActionProposal {
    static let waysShown = 3
    private static let nearCandidates = 10

    static func build(
        chips: [ProposalChip], conditions: [ProposalCondition], gap: ActionGap,
        search: CandidateSearch, walking: WalkingTime
    ) async -> ActionProposalOutcome {
        guard !chips.isEmpty else {
            return ActionProposalOutcome(combinations: [], chipsWithoutPlaces: [], retriedWith: [:])
        }
        let limit = WalkLimit.oneWayMinutes(
            availableMinutes: gap.availableMinutes, walkLess: conditions.contains { $0.kind == .walkLess }
        )
        let radius = WalkLimit.meters(minutes: limit)

        var kept: [(chip: ProposalChip, places: [ProposalPlace])] = []
        var without: [ProposalChip] = []
        var retried: [String: String] = [:]
        for chip in chips {
            let found = await ActionCandidates.gather(for: chip, near: gap.origin, radiusMeters: radius, search: search)
            if let word = found.retriedWith { retried[chip.text] = word }
            if found.places.isEmpty { without.append(chip) } else { kept.append((chip, found.places)) }
        }
        guard !kept.isEmpty else {
            return ActionProposalOutcome(combinations: [], chipsWithoutPlaces: without, retriedWith: retried)
        }

        let direct = await walking(gap.origin, gap.next)
        var ways: [ActionCombination] = []
        for first in kept[0].places.prefix(waysShown) {
            var stops = [ActionCombination.Stop(chip: kept[0].chip, place: first)]
            for next in kept.dropFirst() {
                if let stop = leastDetour(next, after: stops, to: gap.next) { stops.append(stop) }
            }
            ways.append(await timed(stops, gap: gap, direct: direct, walking: walking))
        }
        let ordered = ways.sorted { $0.slackMinutes > $1.slackMinutes }
        return ActionProposalOutcome(combinations: ordered, chipsWithoutPlaces: without, retriedWith: retried)
    }

    /// The place of a chip that adds the least straight-line distance on the way to the next plan, and is not a
    /// place already on the way (the second probe run used one bakery for both パン and 海沿い).
    private static func leastDetour(
        _ entry: (chip: ProposalChip, places: [ProposalPlace]), after stops: [ActionCombination.Stop],
        to next: ProposalPlace
    ) -> ActionCombination.Stop? {
        guard let previous = stops.last?.place else { return nil }
        let unused = entry.places.prefix(nearCandidates).filter { place in
            !stops.contains { ProposalPlace.sameName($0.place.name, place.name) }
        }
        let best = unused.min {
            previous.meters(to: $0) + $0.meters(to: next) < previous.meters(to: $1) + $1.meters(to: next)
        }
        return best.map { ActionCombination.Stop(chip: entry.chip, place: $0) }
    }

    private static func timed(
        _ stops: [ActionCombination.Stop], gap: ActionGap, direct: Int?, walking: WalkingTime
    ) async -> ActionCombination {
        let points = [gap.origin] + stops.map(\.place) + [gap.next]
        var walk = 0
        var missing = false
        for index in 0..<(points.count - 1) {
            if let minutes = await walking(points[index], points[index + 1]) {
                walk += minutes
            } else {
                missing = true
            }
        }
        return ActionCombination(
            stops: stops, walkMinutes: walk, directWalkMinutes: direct,
            stayMinutes: stops.map(\.chip.activity.stayMinutes).reduce(0, +),
            availableMinutes: gap.availableMinutes, missingWalk: missing
        )
    }
}
