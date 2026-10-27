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
    @ObservationIgnored private var generation = 0

    init(
        request: SceneRequest,
        routes: SceneRoutes = SceneRoutes(),
        search: @escaping CandidateSearch = MapKitActionSearch.search
    ) {
        self.request = request
        self.routes = routes
        self.search = search
        states = request.states
        strength = request.strength
    }

    var selected: SceneOption? {
        ways.first { $0.id == selectedID }
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
        let updated = SceneRequest(id: request.id, plans: request.plans, states: states, strength: strength)
        switch updated.input(origin: origin, nowMinutes: nowMinutes) {
        case let .failure(issue): phase = .needsInput(issue)
        case let .success(scene):
            input = scene
            phase = .searching
            routes.retryUnavailable()
            let run = SceneSearchRun(search: search, routes: routes)
            let result = await ActionScene.build(scene, search: run.find, walking: run.walk)
            guard !Task.isCancelled, mine == generation else { return }
            searchFailed = run.searchFailed
            routeFailed = run.routeFailed
            ways = result.enumerated().map { SceneOption(id: ActionProposalModel.letter($0.offset), way: $0.element) }
            phase = .ready
        }
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
    let way: SceneWay
}
