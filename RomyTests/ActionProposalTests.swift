import Foundation
import Testing
@testable import Romy

@MainActor
struct ActionProposalTests {
    // 0.001 degrees of latitude is about 111 m, a minute and a half on foot.
    private let origin = ProposalPlace(name: "いま", latitude: 35.0, longitude: 135.0)
    private let next = ProposalPlace(name: "次の予定", latitude: 35.0, longitude: 135.01)

    private func place(_ name: String, east: Double = 0.003, north: Double = 0.0) -> ProposalPlace {
        ProposalPlace(name: name, latitude: 35.0 + north, longitude: 135.0 + east)
    }

    private func gap(_ minutes: Int) -> ActionGap { ActionGap(origin: origin, next: next, availableMinutes: minutes) }

    private let walking: WalkingTime = { start, end in Int((start.meters(to: end) / 80).rounded(.up)) }

    private let bread = ProposalChip(text: "パン", activity: .buy, query: "パン", category: "bakery")
    private let sea = ProposalChip(text: "海沿い", kind: .abstract, activity: .see, query: "海岸", category: "beach")

    // MARK: Walk limit

    @Test func oneWayWalkIsAQuarterOfTheTimeUpToFifteenMinutes() {
        #expect(WalkLimit.oneWayMinutes(availableMinutes: 40, walkLess: false) == 10)
        #expect(WalkLimit.oneWayMinutes(availableMinutes: 120, walkLess: false) == 15)
        #expect(WalkLimit.oneWayMinutes(availableMinutes: -5, walkLess: false) == 0)
    }

    @Test func walkingLessHalvesTheLimit() {
        #expect(WalkLimit.oneWayMinutes(availableMinutes: 120, walkLess: true) == 7)
    }

    // MARK: Gathering

    @Test func candidatesBeyondTheLimitAreLeftOutAndTheRestComeNearestFirst() async {
        let search: CandidateSearch = { _ in
            [self.place("遠い", east: 0.02), self.place("奥", east: 0.008), self.place("手前", east: 0.002)]
        }
        let found = await ActionCandidates.gather(for: bread, near: origin, radiusMeters: 1000, search: search)
        #expect(found.places.map(\.name) == ["手前", "奥"])
        #expect(found.retriedWith == nil)
    }

    @Test func aChipWithNoHitsIsSearchedAgainWithItsCategoryWord() async {
        let search: CandidateSearch = { query in
            query.text == "パン屋" ? [self.place("ベーカリー")] : []
        }
        let long = ProposalChip(text: "焼きたてのパン", query: "焼きたてのパン", category: "bakery")
        let found = await ActionCandidates.gather(for: long, near: origin, radiusMeters: 1000, search: search)
        #expect(found.places.map(\.name) == ["ベーカリー"])
        #expect(found.retriedWith == "パン屋")
    }

    @Test func theKindOfPlaceIsAskedForFirstAndDroppedWhenItFindsNothing() async {
        var asked: [String?] = []
        let search: CandidateSearch = { query in
            asked.append(query.category)
            return query.category == nil ? [self.place("名前だけの店")] : []
        }
        let found = await ActionCandidates.gather(for: bread, near: origin, radiusMeters: 1000, search: search)
        #expect(asked == ["bakery", nil])
        #expect(found.places.map(\.name) == ["名前だけの店"])
    }

    @Test func aChipWithoutACategoryIsNotRetried() async {
        var count = 0
        let search: CandidateSearch = { _ in
            count += 1
            return []
        }
        let found = await ActionCandidates.gather(
            for: ProposalChip(text: "何か"), near: origin, radiusMeters: 1000, search: search
        )
        #expect(found.places.isEmpty)
        #expect(count == 1)
    }

    // MARK: Combinations

    @Test func aWayThroughTwoPlacesIsTimedInCode() async {
        let search: CandidateSearch = { query in
            query.text == "パン" ? [self.place("パン屋A", east: 0.003)] : [self.place("海A", east: 0.006, north: 0.001)]
        }
        let outcome = await ActionProposal.build(
            chips: [bread, sea], conditions: [], gap: gap(120), search: search, walking: walking
        )
        let way = outcome.combinations.first
        #expect(way?.stops.map(\.place.name) == ["パン屋A", "海A"])
        #expect(way?.stayMinutes == 10 + 30)
        #expect(way?.totalMinutes == (way?.walkMinutes ?? 0) + 40 + ActionGap.marginMinutes)
        #expect(way?.fits == true)
        #expect(way?.detourWalkMinutes != nil)
    }

    @Test func theDetourWalkIsTheTotalMinusTheWalkStraightToTheNextPlan() async {
        let search: CandidateSearch = { _ in [self.place("パン屋A", east: 0.003, north: 0.002)] }
        let outcome = await ActionProposal.build(
            chips: [bread], conditions: [], gap: gap(120), search: search, walking: walking
        )
        let way = outcome.combinations.first
        let direct = way?.directWalkMinutes ?? 0
        #expect(way?.detourWalkMinutes == max(0, (way?.walkMinutes ?? 0) - direct))
        #expect((way?.detourWalkMinutes ?? 0) <= (way?.walkMinutes ?? 0))
    }

    @Test func aLongDetourIsMarkedWhenWalkingLessAndStillShown() async {
        // Bread to the west, the sea to the north: both inside the halved limit, but the way out and back
        // adds more than twice that limit (about 19 minutes against 14).
        let search: CandidateSearch = { query in
            query.text == "パン" ? [self.place("パン屋A", east: -0.006)] : [self.place("海A", east: 0, north: 0.005)]
        }
        let walkLess = ProposalCondition(text: "あまり歩きたくない", kind: .walkLess)
        let less = await ActionProposal.build(
            chips: [bread, sea], conditions: [walkLess], gap: gap(120), search: search, walking: walking
        )
        let normal = await ActionProposal.build(
            chips: [bread, sea], conditions: [], gap: gap(120), search: search, walking: walking
        )
        #expect(less.combinations.first?.detourLimitMinutes == 14)
        #expect(less.combinations.first?.walksMoreThanAsked == true)
        #expect(normal.combinations.first?.detourLimitMinutes == nil)
        #expect(normal.combinations.first?.walksMoreThanAsked == false)
        #expect(less.combinations.count == normal.combinations.count)
    }

    @Test func aShortDetourIsNotMarkedWhenWalkingLess() async {
        let search: CandidateSearch = { _ in [self.place("パン屋A", east: 0.003)] }
        let walkLess = ProposalCondition(text: "あまり歩きたくない", kind: .walkLess)
        let outcome = await ActionProposal.build(
            chips: [bread], conditions: [walkLess], gap: gap(120), search: search, walking: walking
        )
        #expect(outcome.combinations.first?.walksMoreThanAsked == false)
    }

    @Test func aWayThatDoesNotFitKeepsHowManyMinutesItIsShort() async {
        let search: CandidateSearch = { _ in [self.place("パン屋A")] }
        let eat = ProposalChip(text: "ランチ", activity: .eat)
        let outcome = await ActionProposal.build(
            chips: [eat], conditions: [], gap: gap(50), search: search, walking: walking
        )
        let way = outcome.combinations.first
        #expect(way?.fits == false)
        #expect((way?.shortfallMinutes ?? 0) > 0)
        #expect(way?.shortfallMinutes == -(way?.slackMinutes ?? 0))
    }

    @Test func aChipWithNoPlacesIsReportedAndTheOthersStillMakeAWay() async {
        let search: CandidateSearch = { query in query.text == "パン" ? [self.place("パン屋A")] : [] }
        let outcome = await ActionProposal.build(
            chips: [bread, sea], conditions: [], gap: gap(120), search: search, walking: walking
        )
        #expect(outcome.chipsWithoutPlaces == [sea])
        #expect(outcome.combinations.first?.stops.map(\.chip) == [bread])
    }

    @Test func noPlacesForAnyChipGivesNoWays() async {
        let outcome = await ActionProposal.build(
            chips: [bread, sea], conditions: [], gap: gap(120), search: { _ in [] }, walking: walking
        )
        #expect(outcome.isEmpty)
        #expect(outcome.chipsWithoutPlaces == [bread, sea])
    }

    @Test func theSamePlaceIsNotUsedForTwoChips() async {
        let search: CandidateSearch = { _ in [self.place("イスズベーカリー", east: 0.003), self.place("海の家", east: 0.004)] }
        let outcome = await ActionProposal.build(
            chips: [bread, sea], conditions: [], gap: gap(120), search: search, walking: walking
        )
        let names = outcome.combinations.flatMap { $0.stops.map(\.place.name) }
        for way in outcome.combinations {
            #expect(Set(way.stops.map(\.place.name)).count == way.stops.count)
        }
        #expect(!names.isEmpty)
    }

    @Test func aWalkWithNoAnswerMakesTheTimeUnknownNotInvented() async {
        let search: CandidateSearch = { _ in [self.place("パン屋A")] }
        let outcome = await ActionProposal.build(
            chips: [bread], conditions: [], gap: gap(120), search: search, walking: { _, _ in nil }
        )
        let way = outcome.combinations.first
        #expect(way?.missingWalk == true)
        #expect(way?.fits == false)
        #expect(way?.shortfallMinutes == 0)
    }

    @Test func walkingLessNarrowsWhereToLook() async {
        // 12 minutes on foot east (about 960 m): inside the 15-minute limit, outside the halved one.
        let search: CandidateSearch = { _ in [self.place("やや遠い", east: 0.0105)] }
        let normal = await ActionProposal.build(
            chips: [bread], conditions: [], gap: gap(120), search: search, walking: walking
        )
        let less = await ActionProposal.build(
            chips: [bread], conditions: [ProposalCondition(text: "あまり歩きたくない", kind: .walkLess)],
            gap: gap(120), search: search, walking: walking
        )
        #expect(!normal.isEmpty)
        #expect(less.isEmpty)
    }

    // MARK: Checks and names

    @Test func aYesNeedsASourceAndNoDoubt() {
        #expect(CheckResult.from(answer: "yes", isOfficial: true, sourceCount: 1, detail: "営業中") == .official)
        #expect(CheckResult.from(answer: "yes", isOfficial: false, sourceCount: 2, detail: "") == .introduced)
        #expect(CheckResult.from(answer: "yes", isOfficial: true, sourceCount: 0, detail: "") == .unknown)
        #expect(CheckResult.from(answer: "yes", isOfficial: true, sourceCount: 1, detail: "確証はない") == .unknown)
        #expect(CheckResult.from(answer: "yes", isOfficial: true, sourceCount: 1, detail: "確認できます") == .official)
        #expect(CheckResult.from(answer: "no", isOfficial: true, sourceCount: 1, detail: "") == .contradicted)
        #expect(CheckResult.from(answer: "unknown", isOfficial: false, sourceCount: 0, detail: "") == .unknown)
    }

    @Test func namesMatchOnceBranchWordsAreDropped() {
        #expect(ProposalPlace.sameName("イスズベーカリー 本店", "イスズベーカリー"))
        #expect(ProposalPlace.sameName("ＡＢＣ カフェ", "abcカフェ"))
        #expect(!ProposalPlace.sameName("パン屋A", "海の家"))
    }
}

@MainActor
struct ActionIntakeTests {
    @Test func knownWordsBecomeChipsWithAKindOfPlace() {
        guard case .chip(let bread)? = ActionIntake.parse("パンを買う") else {
            Issue.record("not a chip")
            return
        }
        #expect(bread.category == "bakery")
        #expect(bread.activity == .buy)
        #expect(bread.text == "パンを買う")
    }

    @Test func notWantingToWalkIsAConditionNotAChip() {
        let walkLess = ProposalCondition(text: "歩くのは少なめ", kind: .walkLess)
        #expect(ActionIntake.parse("あまり歩きたくない") == .condition(walkLess))
    }

    @Test func anythingElseIsSearchedAsWritten() {
        #expect(ActionIntake.parse("  神社  ") == .chip(ProposalChip(text: "神社")))
        #expect(ActionIntake.parse("   ") == nil)
    }

    @Test func widerSearchAddsMinutesPastTheCap() {
        #expect(WalkLimit.oneWayMinutes(availableMinutes: 120, walkLess: false, widerBy: 5) == 20)
    }

    @Test func aMapThatCannotBeAskedIsNotTheSameAsNothingFound() async {
        struct Offline: Error {}
        let origin = ProposalPlace(name: "いま", latitude: 35.0, longitude: 135.0)
        let next = ProposalPlace(name: "次", latitude: 35.0, longitude: 135.01)
        let outcome = await ActionProposal.build(
            chips: [ProposalChip(text: "パン", category: "bakery")], conditions: [],
            gap: ActionGap(origin: origin, next: next, availableMinutes: 120),
            search: { _ in throw Offline() }, walking: { _, _ in 5 }
        )
        #expect(outcome.chipsFailed.count == 1)
        #expect(outcome.chipsWithoutPlaces.isEmpty)
        #expect(outcome.isEmpty)
    }

    @Test func theOpportunityIsTheNextPlanWithAPlace() {
        let now = ItineraryItem(title: "いま", day: 1, order: 0, kind: .sight, latitude: 35.0, longitude: 135.0)
        let nameOnly = ItineraryItem(title: "名前だけ", day: 1, order: 1, kind: .other)
        let next = ItineraryItem(title: "次", day: 1, order: 2, kind: .sight, latitude: 35.0, longitude: 135.01)
        next.fixedStartMinutes = 15 * 60
        let schedule = DaySchedule(dayStartMinutes: 9 * 60, plans: [now, nameOnly, next].map {
            DaySchedule.Input(id: $0.id, durationMinutes: 30, fixedStartMinutes: $0.fixedStartMinutes)
        })
        let plans = [now, nameOnly, next]
        let found = ActionOpportunity.make(after: now, in: plans, schedule: schedule, nowMinutes: 13 * 60)
        #expect(found?.nextTitle == "次")
        #expect(found?.availableMinutes == 120)
        #expect(found?.nextIsFixed == true)
        #expect(ActionOpportunity.make(after: next, in: plans, schedule: schedule, nowMinutes: 0) == nil)
    }
}
