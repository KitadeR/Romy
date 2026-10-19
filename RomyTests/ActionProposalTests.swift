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
