import CoreLocation
import Foundation
import Observation

/// What the 「候補を比べる」 sheet shows and does: the chips, the search, and the ways found (Notion 02 §6-4,
/// Figma 24案). The chips are typed in until the model that splits a wish is added (`ActionIntake`).
@Observable
final class ActionProposalModel {
    enum Phase: Equatable {
        /// No chips yet.
        case empty
        case searching
        /// The person's place is not known and the plan's place was not chosen (Figma 24案 02).
        case needsLocation
        case done
    }

    /// What 「もう少し遠くも」 adds to the walk each time, in minutes.
    static let widerStep = 5

    let opportunity: ActionOpportunity
    private(set) var chips: [ProposalChip] = []
    private(set) var conditions: [ProposalCondition] = []
    private(set) var outcome: ActionProposalOutcome?
    private(set) var phase: Phase = .empty
    private(set) var widerBy = 0
    private(set) var startsFromPlan = false

    @ObservationIgnored private let location: LocationProvider
    @ObservationIgnored private let searchPlaces: CandidateSearch
    @ObservationIgnored private let walking: WalkingTime
    @ObservationIgnored private var generation = 0

    init(
        opportunity: ActionOpportunity, location: LocationProvider,
        search: @escaping CandidateSearch = MapKitActionSearch.search,
        walking: @escaping WalkingTime = MapKitActionSearch.walkingMinutes
    ) {
        self.opportunity = opportunity
        self.location = location
        self.searchPlaces = search
        self.walking = walking
    }

    /// 「A」「B」「C」 for the ways in order.
    static func letter(_ index: Int) -> String {
        String(UnicodeScalar(UInt8(ascii: "A") + UInt8(index)))
    }

    /// 「パンを買う」→「パン」: the noun of a chip, for a sentence like 「近くにパンは見つかりませんでした」.
    static func stem(_ text: String) -> String {
        for suffix in ["を買う", "を食べる", "で食べる", "で休む", "を探す", "に行く", "を見る"] where text.hasSuffix(suffix) {
            return String(text.dropLast(suffix.count))
        }
        return text
    }

    var isWalkingLess: Bool { conditions.contains { $0.kind == .walkLess } }

    /// How far the search went on foot, one way, in minutes.
    var limitMinutes: Int {
        WalkLimit.oneWayMinutes(
            availableMinutes: opportunity.availableMinutes, walkLess: isWalkingLess, widerBy: widerBy
        )
    }

    var canUsePlanPlace: Bool { opportunity.currentPlace != nil }

    /// Changes when the place the search starts from becomes known, so the sheet searches then.
    var originKey: String { "\(origin != nil)-\(startsFromPlan)" }

    private var origin: ProposalPlace? {
        if startsFromPlan { return opportunity.currentPlace }
        guard let here = location.location else { return nil }
        return ProposalPlace(name: "いまの場所", latitude: here.coordinate.latitude, longitude: here.coordinate.longitude)
    }

    // MARK: - Edits

    /// Adds what the person typed as a chip or a condition; false when there was nothing to add.
    @discardableResult
    func add(_ text: String) -> Bool {
        switch ActionIntake.parse(text) {
        case .chip(let chip)?:
            guard !chips.contains(chip) else { return false }
            chips.append(chip)
        case .condition(let condition)?:
            guard !conditions.contains(condition) else { return false }
            conditions.append(condition)
        case nil:
            return false
        }
        rerun()
        return true
    }

    func remove(_ chip: ProposalChip) {
        chips.removeAll { $0 == chip }
        rerun()
    }

    func remove(_ condition: ProposalCondition) {
        conditions.removeAll { $0 == condition }
        rerun()
    }

    func searchWider() {
        widerBy += Self.widerStep
        rerun()
    }

    func startFromPlan() {
        startsFromPlan = true
        rerun()
    }

    func rerun() {
        Task { await refresh() }
    }

    // MARK: - Search

    func refresh() async {
        generation += 1
        let mine = generation
        guard !chips.isEmpty else {
            outcome = nil
            phase = .empty
            return
        }
        guard let origin else {
            outcome = nil
            phase = .needsLocation
            return
        }
        phase = .searching
        let gap = ActionGap(origin: origin, next: opportunity.next, availableMinutes: opportunity.availableMinutes)
        let result = await ActionProposal.build(
            chips: chips, conditions: conditions, gap: gap, widerBy: widerBy, search: searchPlaces, walking: walking
        )
        guard mine == generation else { return }
        outcome = result
        phase = .done
    }
}
