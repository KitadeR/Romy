import Foundation
import Observation

@Observable
final class ActionSceneModel {
    enum Phase: Equatable { case empty, searching, needsInput(SceneRequest.Issue), ready }

    enum Refinement { case closer, others }

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
    private(set) var note: String
    private(set) var preferences = ScenePreferences()
    private(set) var noteFailed = false
    private(set) var isRefining = false
    private(set) var refinementMessage: String?
    private(set) var resultsVersion = 0
    private(set) var hours: [String: SceneHours] = [:]
    private(set) var checkingHours: Set<String> = []
    private(set) var sessionID = UUID()
    var selectedID: String?
    /// How long the person means to spend, when nothing in the itinerary ends the time (「あと何時間すごす？」).
    var chosenMinutes = ActionSceneModel.defaultChosenMinutes
    static let defaultChosenMinutes = 90
    static let chosenRange = 30...300
    @ObservationIgnored private let search: CandidateSearch
    @ObservationIgnored private let facts: LuggageFacts
    @ObservationIgnored private let ai: SceneAI
    @ObservationIgnored private var interpretation: Task<ScenePreferences?, Never>?
    @ObservationIgnored private var interpretedNote: String?
    @ObservationIgnored private var seenPlaces: Set<String> = []
    @ObservationIgnored private var searchAICount = 0
    @ObservationIgnored private var attemptedHours: Set<String> = []
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var generation = 0

    init(
        request: SceneRequest,
        routes: SceneRoutes = SceneRoutes(),
        search: @escaping CandidateSearch = MapKitActionSearch.search,
        facts: LuggageFacts = .off,
        ai: SceneAI = .live,
        now: @escaping () -> Date = Date.init
    ) {
        self.request = request
        self.routes = routes
        self.search = search
        self.facts = facts
        self.ai = ai
        note = request.note
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
        let availability = hours.values.contains { $0.status == "official" }
            ? "ロッカーや席の空きは確認していません。営業時間は詳細の確認結果をご覧ください。"
            : "ロッカーや席の空き・営業時間は確認していません。営業時間は詳細で確認できます。"
        return checked
            ? "地図は徒歩経路。時間は目安です。宿の荷物預かりはAIが調べた公開情報です。" + availability
            : "地図は徒歩経路。時間は目安です。荷物預かり・" + availability
    }

    func edit(states: Set<ActionState>, strength: TiredStrength?, note: String? = nil) {
        self.states = states
        self.strength = strength
        if let note, note != self.note {
            self.note = note
            // 一言を変更したときだけ新しいセッションにする。絞り直しではAIを呼び直さない。
            sessionID = UUID()
            interpretation?.cancel()
            interpretation = nil
            interpretedNote = nil
            noteFailed = false
            preferences = ScenePreferences()
            searchAICount = 0
            attemptedHours = []
            checkingHours = []
        }
        seenPlaces = []
    }

    func removeCondition(at index: Int) {
        let keys = [preferences.query != nil, preferences.walkMinutes != nil,
                    preferences.restMinutes != nil, preferences.totalMinutes != nil]
        let active = keys.indices.filter { keys[$0] }
        guard active.indices.contains(index) else { return }
        switch active[index] {
        case 0: preferences.query = nil; preferences.category = nil
        case 1: preferences.walkMinutes = nil
        case 2: preferences.restMinutes = nil
        default: preferences.totalMinutes = nil
        }
        seenPlaces = []
    }

    func refresh(origin: ProposalPlace?, nowMinutes: Int, usesPlanPlace: Bool,
                 refinement: Refinement? = nil) async {
        generation += 1
        let mine = generation
        let keepsResults = refinement != nil && !ways.isEmpty
        isRefining = keepsResults
        defer { if mine == generation { isRefining = false } }
        refinementMessage = nil
        if !keepsResults { selectedID = nil; ways = []; input = nil }
        searchFailed = false
        routeFailed = false
        self.usesPlanPlace = usesPlanPlace
        guard !states.isEmpty || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .empty; return
        }
        guard origin != nil else { phase = .needsInput(.needsLocation); return }
        if interpretedNote != note, !note.isEmpty {
            phase = .searching
            let session = sessionID
            if interpretation == nil {
                let text = note
                // 位置取得や条件変更でViewのtaskが作り直されても、同じ一言を二重送信しない。
                interpretation = Task { await ai.interpret(text, session) }
            }
            let interpreted = await interpretation?.value
            guard session == sessionID else { return }
            if interpretedNote != note {
                interpretedNote = note
                noteFailed = interpreted?.isValid != true
                preferences = interpreted.flatMap { $0.isValid ? $0 : nil } ?? ScenePreferences()
            }
            guard !Task.isCancelled, mine == generation else { return }
        }
        if states.isEmpty, preferences.captions.isEmpty {
            phase = .empty; return
        }
        var effective = preferences
        if refinement == .closer {
            let current = ways.compactMap { $0.way.steps.first?.walkBeforeMinutes }.min() ?? 10
            effective.walkMinutes = max(1, min(effective.walkMinutes ?? 30, current - 1))
        }
        let updated = SceneRequest(
            id: request.id, plans: request.plans, states: states, strength: strength,
            currentStartMinutes: request.currentStartMinutes, freeDay: request.freeDay,
            searchDate: request.searchDate, note: note
        )
        switch updated.input(origin: origin, nowMinutes: nowMinutes,
                             chosenMinutes: effective.totalMinutes ?? chosenMinutes) {
        case let .failure(issue):
            if !keepsResults { phase = .needsInput(issue) }
        case var .success(scene):
            scene.preferences = effective
            if !keepsResults { input = scene; phase = .searching }
            routes.retryUnavailable()
            let (known, asking) = luggage(for: scene)
            let excluded = refinement == .others ? seenPlaces : []
            let run = SceneSearchRun(search: search, routes: routes)
            let result = await ActionScene.build(
                scene, search: { query in
                    try await run.find(query).filter { !excluded.contains($0.scenePlaceKey) }
                }, walking: run.walk, luggageCheck: { _ in known?.result ?? .unknown }
            )
            guard !Task.isCancelled, mine == generation else { return }
            searchFailed = run.searchFailed
            routeFailed = run.routeFailed
            if keepsResults, result.isEmpty {
                refinementMessage = searchFailed || routeFailed
                    ? "調べられませんでした。表示中の案はそのままです。"
                    : "条件に合う別の案は見つかりませんでした。"
                phase = .ready
                return
            }
            input = scene
            preferences = effective
            selectedID = nil
            ways = result.enumerated().map { index, way in
                let mark: LuggageMark = !way.leavesLuggageAtStay ? .none
                    : known.map { .checked($0) } ?? (asking != nil && refinement == nil ? .checking : .none)
                return SceneOption(id: ActionProposalModel.letter(index), way: way, luggage: mark)
            }
            for option in ways {
                for step in option.way.steps where step.kind == .rest || step.kind == .eat {
                    seenPlaces.insert(step.place.scenePlaceKey)
                }
            }
            resultsVersion += 1
            phase = .ready
            if let asking, refinement == nil { await ask(asking, generation: mine) }
        }
    }

    /// 詳細を開いた店だけを確認する。取得中も順番・経路・選択中のカードは変えない。
    func checkHours(for option: SceneOption) async {
        let session = sessionID
        for step in option.way.steps where step.kind == .rest || step.kind == .eat {
            let key = step.place.scenePlaceKey
            guard !Task.isCancelled, session == sessionID else { return }
            if hours[key]?.isFresh(on: request.searchDate, at: now()) == true { continue }
            guard !attemptedHours.contains(key), searchAICount < 3 else { continue }
            attemptedHours.insert(key)
            searchAICount += 1
            checkingHours.insert(key)
            let fact = await ai.hours(step.place, request.searchDate, session)
            guard session == sessionID else { return }
            checkingHours.remove(key)
            guard !Task.isCancelled else { return }
            if let fact, fact.isFresh(on: request.searchDate, at: now()) { hours[key] = fact }
        }
    }

    func isCheckingHours(for option: SceneOption) -> Bool {
        option.way.steps.contains { checkingHours.contains($0.place.scenePlaceKey) }
    }

    func hoursPermit(_ option: SceneOption) -> Bool {
        option.way.steps.filter { $0.kind == .rest || $0.kind == .eat }.allSatisfy { step in
            guard let fact = hours[step.place.scenePlaceKey],
                  fact.isFresh(on: request.searchDate, at: now()) else { return true }
            return fact.permits(step)
        }
    }

    /// 旅程は確定まで触らず、編集中の案にだけ差し替え結果を持たせる。
    func replacements(for option: SceneOption, at index: Int) async -> SceneAlternatives {
        guard let input, option.way.steps.indices.contains(index) else { return SceneAlternatives() }
        let step = option.way.steps[index]
        guard step.kind == .rest || step.kind == .eat else { return SceneAlternatives() }
        let basis = generation
        let origin = index == 0 ? input.origin : option.way.steps[index - 1].place
        let run = SceneSearchRun(search: search, routes: routes)
        routes.retryUnavailable()
        let found = await ActionCandidates.gather(
            for: ActionScene.seatChip(for: input),
            near: origin, radiusMeters: ActionScene.searchRadius(for: input),
            allowCategoryFallback: input.preferences.query == nil, search: run.find
        )
        var result = SceneAlternatives()
        var seen = Set(option.way.steps.map { $0.place.scenePlaceKey })
        for place in found.places where seen.insert(place.scenePlaceKey).inserted {
            guard !Task.isCancelled, generation == basis else { return SceneAlternatives() }
            var stops = option.way.steps.map { ActionScene.Planned($0.kind, $0.title, $0.place, unknown: $0.isUnknown) }
            stops[index] = ActionScene.Planned(step.kind, place.name, place)
            let reason = option.way.reason == .leastWalk ? SceneWay.Reason.otherSeat : option.way.reason
            guard let way = await ActionScene.timed(reason, stops, input: input, walking: run.walk),
                  ActionScene.meetsWalkingLimits(way, strength: input.strength, walkLimit: input.preferences.walkMinutes) else { continue }
            result.choices.append(SceneReplacement(optionID: option.id, generation: basis, index: index,
                                                  original: step.place, place: place, way: way))
            if result.choices.count == ActionScene.waysShown { break }
        }
        result.incomplete = found.failed || run.routeFailed
        return result
    }

    @discardableResult
    func replace(_ choice: SceneReplacement) -> Bool {
        guard generation == choice.generation, choice.way.fits,
              let index = ways.firstIndex(where: { $0.id == choice.optionID }),
              !ways[index].isUnavailable, ways[index].way.steps[choice.index].place == choice.original
        else { return false }
        var way = choice.way
        // 候補を調べている間に届いた宿の確認結果も、新しい案へ引き継ぐ。
        if case .checked(let fact) = ways[index].luggage,
           fact.result == .official || fact.result == .introduced {
            way = way.knowingLuggageIsKept()
        }
        ways[index].way = way
        if way.reason == .otherSeat {
            for other in ways.indices where ways[other].way.reason == .leastWalk
                && ways[other].way.walkMinutes > way.walkMinutes {
                ways[other].way.reason = .otherSeat
            }
        }
        return true
    }

    /// The stay's check when it is kept and fresh; otherwise the stay to ask about now, when the person allowed it
    /// (Notion 02 §6-4「決定（2026-10-29）｜事実の確認⑤」).
    private func luggage(for scene: SceneInput) -> (known: LuggageFact?, asking: ItineraryItemSnapshot?) {
        guard scene.hasHeavyLuggage, scene.stay != nil,
              let stay = request.ahead(nowMinutes: scene.nowMinutes)?.stay else { return (nil, nil) }
        let key = LuggageFact.placeKey(title: stay.title, placeID: stay.placeID, area: stay.area)
        if let fact = facts.stored(stay.id), fact.placeKey == key, fact.isFresh(at: now()) { return (fact, nil) }
        return (nil, facts.allowed() ? stay : nil)
    }

    /// The answer changes only the mark (and the headline of a ✓) of the way it belongs to; the order stays
    /// while the person is looking (Figma 23 2版 02・03).
    private func ask(_ stay: ItineraryItemSnapshot, generation mine: Int) async {
        guard searchAICount < 3 else { return }
        searchAICount += 1
        let fact: LuggageFact?
        if let check = facts.inSession { fact = await check(stay, sessionID) }
        else { fact = await facts.check(stay) }
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

extension ProposalPlace {
    var scenePlaceKey: String { placeID ?? "\(latitude),\(longitude):\(name)" }
}

struct SceneReplacement: Identifiable {
    let optionID: String
    let generation: Int
    let index: Int
    let original: ProposalPlace
    let place: ProposalPlace
    let way: SceneWay
    var id: String { place.scenePlaceKey }
}

struct SceneAlternatives {
    var choices: [SceneReplacement] = []
    var incomplete = false
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
    var inSession: ((ItineraryItemSnapshot, UUID) async -> LuggageFact?)?

    static let off = LuggageFacts(stored: { _ in nil }, check: { _ in nil }, save: { _, _ in }, allowed: { false })
}
