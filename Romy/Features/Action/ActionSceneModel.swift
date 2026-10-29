import Foundation
import Observation

@Observable
final class ActionSceneModel {
    enum Phase: Equatable { case empty, searching, needsInput(SceneRequest.Issue), ready }

    let request: SceneRequest
    let routes: SceneRoutes
    private(set) var states: Set<ActionState>
    private(set) var strength: TiredStrength?
    private(set) var phase: Phase = .searching
    private(set) var input: SceneInput?
    private(set) var ways: [SceneOption] = []
    private(set) var searchFailed = false
    private(set) var routeFailed = false
    private(set) var usesPlanPlace = false
    var selectedID: String?
    @ObservationIgnored private let search: CandidateSearch
    @ObservationIgnored private let facts: LuggageFacts
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var generation = 0

    init(
        request: SceneRequest,
        routes: SceneRoutes = SceneRoutes(),
        search: @escaping CandidateSearch = MapKitActionSearch.search,
        facts: LuggageFacts = .off,
        now: @escaping () -> Date = Date.init
    ) {
        self.request = request
        self.routes = routes
        self.search = search
        self.facts = facts
        self.now = now
        states = request.states
        strength = request.strength
    }

    var selected: SceneOption? {
        ways.first { $0.id == selectedID }
    }

    /// The note under the ways. Once the stay's answer is in, its luggage line is no longer 「確認していません」.
    var footnote: String {
        let checked = ways.contains { option in
            if case .checked = option.luggage { return true }
            return false
        }
        return checked
            ? "地図は徒歩経路。時間は目安です。宿の荷物預かりはAIが調べた公開情報です。ロッカーや席の空き・営業時間は確認していません。"
            : "地図は徒歩経路。時間は目安です。荷物預かり・ロッカーや席の空き・営業時間は確認していません。"
    }

    func edit(states: Set<ActionState>, strength: TiredStrength?) {
        self.states = states
        self.strength = strength
    }

    func refresh(origin: ProposalPlace?, nowMinutes: Int, usesPlanPlace: Bool) async {
        generation += 1
        let mine = generation
        selectedID = nil
        ways = []
        input = nil
        searchFailed = false
        routeFailed = false
        self.usesPlanPlace = usesPlanPlace
        guard !states.isEmpty else { phase = .empty; return }
        let updated = SceneRequest(
            id: request.id, plans: request.plans, states: states, strength: strength,
            currentStartMinutes: request.currentStartMinutes
        )
        switch updated.input(origin: origin, nowMinutes: nowMinutes) {
        case let .failure(issue): phase = .needsInput(issue)
        case let .success(scene):
            input = scene
            phase = .searching
            routes.retryUnavailable()
            let (known, asking) = luggage(for: scene)
            let run = SceneSearchRun(search: search, routes: routes)
            let result = await ActionScene.build(
                scene, search: run.find, walking: run.walk, luggageCheck: { _ in known?.result ?? .unknown }
            )
            guard !Task.isCancelled, mine == generation else { return }
            searchFailed = run.searchFailed
            routeFailed = run.routeFailed
            ways = result.enumerated().map { index, way in
                let mark: LuggageMark = !way.leavesLuggageAtStay ? .none
                    : known.map { .checked($0) } ?? (asking != nil ? .checking : .none)
                return SceneOption(id: ActionProposalModel.letter(index), way: way, luggage: mark)
            }
            phase = .ready
            if let asking { await ask(asking, generation: mine) }
        }
    }

    /// The stay's check when it is kept and fresh; otherwise the stay to ask about now, when the person allowed it
    /// (Notion 02 §6-4「決定（2026-10-29）｜事実の確認⑤」).
    private func luggage(for scene: SceneInput) -> (known: LuggageFact?, asking: ItineraryItemSnapshot?) {
        guard scene.hasHeavyLuggage, scene.stay != nil, let stay = request.ahead()?.stay else { return (nil, nil) }
        let key = LuggageFact.placeKey(title: stay.title, placeID: stay.placeID, area: stay.area)
        if let fact = facts.stored(stay.id), fact.placeKey == key, fact.isFresh(at: now()) { return (fact, nil) }
        return (nil, facts.allowed() ? stay : nil)
    }

    /// The answer changes only the mark (and the headline of a ✓) of the way it belongs to; the order stays
    /// while the person is looking (Figma 23 2版 02・03).
    private func ask(_ stay: ItineraryItemSnapshot, generation mine: Int) async {
        let fact = await facts.check(stay)
        guard !Task.isCancelled, mine == generation else { return }
        if let fact { facts.save(stay.id, fact) }
        ways = ways.map { $0.answered(fact) }
    }
}

/// Diagnostics belong destination one run, so a cancelled/older search cannot overwrite the current result.
private final class SceneSearchRun {
    var searchFailed = false
    var routeFailed = false
    let search: CandidateSearch
    let routes: SceneRoutes
    private var found: [(CandidateQuery, [ProposalPlace])] = []

    init(search: @escaping CandidateSearch, routes: SceneRoutes) {
        self.search = search; self.routes = routes
    }

    func find(_ query: CandidateQuery) async throws -> [ProposalPlace] {
        try Task.checkCancellation()
        if let cached = found.first(where: { $0.0 == query }) {
            return cached.1
        }
        do {
            let places = try await search(query)
            found.append((query, places))
            return places
        } catch {
            searchFailed = true
            throw error
        }
    }

    func walk(_ from: ProposalPlace, _ destination: ProposalPlace) async -> Int? {
        guard !Task.isCancelled else { return nil }
        let value = await routes.minutes(from, destination)
        if value == nil {
            routeFailed = true
        }
        return value
    }
}

struct SceneOption: Identifiable {
    let id: String
    var way: SceneWay
    var luggage: LuggageMark = .none

    /// ✗ arrived: the row stays where it is, dimmed, and cannot be chosen (Figma 23 2版 03).
    var isUnavailable: Bool {
        if case .checked(let fact) = luggage { return fact.result == .contradicted }
        return false
    }

    var luggageCaption: String? {
        switch luggage {
        case .none: nil
        case .checking: "宿で預けられるか確認中…"
        case .checked(let fact): fact.caption
        }
    }

    /// The check came back (nil: nothing came back, so the way stays 「？」).
    func answered(_ fact: LuggageFact?) -> SceneOption {
        guard luggage == .checking else { return self }
        var option = self
        guard let fact else {
            option.luggage = .none
            return option
        }
        option.luggage = .checked(fact)
        if fact.result == .official || fact.result == .introduced { option.way = way.knowingLuggageIsKept() }
        return option
    }
}

/// Where Romy Now gets the luggage check of the stay ahead: kept on the stay, or asked now.
struct LuggageFacts {
    var stored: (UUID) -> LuggageFact?
    var check: (ItineraryItemSnapshot) async -> LuggageFact?
    var save: (UUID, LuggageFact) -> Void
    var allowed: () -> Bool

    static let off = LuggageFacts(stored: { _ in nil }, check: { _ in nil }, save: { _, _ in }, allowed: { false })
}
