import Foundation
import Testing
@testable import Romy

/// A stay that opens at 15:00 (「15:00から」) and the scene of the question feature (Notion 02 §6-4, 2026-10-25):
/// 14:00, tired, heavy luggage, the stay from 15:00, a booked dinner at 17:00.
@MainActor
struct ActionSceneTests {
    // MARK: 「15:00から」 in the day's times

    private func plan(_ duration: Int, fixed: Int? = nil, notBefore: Int? = nil) -> DaySchedule.Input {
        DaySchedule.Input(id: UUID(), durationMinutes: duration, fixedStartMinutes: fixed, notBeforeMinutes: notBefore)
    }

    @Test func aGuessEarlierThanCheckInWaitsUntilItOpens() {
        let schedule = DaySchedule(dayStartMinutes: 13 * 60, plans: [plan(60), plan(90, notBefore: 15 * 60), plan(60)])
        #expect(schedule.slots.map(\.startMinutes) == [13 * 60, 15 * 60, 16 * 60 + 30])
        #expect(schedule.slots[1].isFixed == false)
    }

    @Test func aLaterGuessIsNotPulledBackToCheckIn() {
        let schedule = DaySchedule(dayStartMinutes: 15 * 60, plans: [plan(60), plan(60, notBefore: 15 * 60)])
        #expect(schedule.slots[1].startMinutes == 16 * 60)
    }

    @Test func aFixedStartWinsOverCheckIn() {
        let schedule = DaySchedule(
            dayStartMinutes: 13 * 60, plans: [plan(30), plan(60, fixed: 14 * 60, notBefore: 15 * 60)]
        )
        #expect(schedule.slots[1].startMinutes == 14 * 60)
        #expect(schedule.slots[1].isFixed)
    }

    // MARK: The scene

    // 0.001 degrees of longitude here is about 91 m; walking is the straight line at 80 m a minute.
    private func place(_ name: String, east: Double, north: Double = 0) -> ProposalPlace {
        ProposalPlace(name: name, latitude: 35.0 + north, longitude: 135.0 + east)
    }

    private var origin: ProposalPlace { place("今いる所", east: 0) }
    private var hotel: ProposalPlace { place("ホテル", east: 0.006) }
    private var dinner: ProposalPlace { place("お店", east: 0.009, north: 0.002) }
    private let walking: WalkingTime = { start, end in Int((start.meters(to: end) / 80).rounded(.up)) }

    private var search: CandidateSearch {
        let cafeHere = place("駅前カフェ", east: 0.002)
        let cafeByHotel = place("宿のそばのカフェ", east: 0.0065, north: 0.0005)
        let locker = place("駅のロッカー", east: 0.001, north: -0.001)
        let diner = place("食堂", east: 0.0025)
        return { query in
            switch query.text {
            case "カフェ": [cafeHere, cafeByHotel]
            case "コインロッカー": [locker]
            case "レストラン": [diner]
            default: []
            }
        }
    }

    private func input(
        _ states: Set<ActionState>, strength: TiredStrength? = .quite, checkIn: Int? = 15 * 60, now: Int = 14 * 60
    ) -> SceneInput {
        SceneInput(
            nowMinutes: now, origin: origin,
            stay: SceneInput.Stay(title: "ホテル", place: hotel, checkInMinutes: checkIn),
            nextTitle: "お店", next: dinner, nextStartMinutes: 17 * 60, states: states, strength: strength
        )
    }

    @Test func withAnUnknownDropTheWayThatDoesNotNeedItComesFirst() async {
        let ways = await ActionScene.build(input([.tired, .heavyLuggage]), search: search, walking: walking)
        #expect(ways.first?.reason == .leastWalk)
        #expect(ways.contains { $0.reason == .dropIfAllowed })
        #expect(ways.first?.hasUnknown == false)
        let ifAllowed = ways.first { $0.reason == .dropIfAllowed }
        #expect(ifAllowed?.steps.first?.isUnknown == true)
    }

    @Test func aKnownDropComesFirstWithHeavyLuggage() async {
        let ways = await ActionScene.build(
            input([.tired, .heavyLuggage]), search: search, walking: walking, luggageCheck: { _ in .official }
        )
        #expect(ways.first?.reason == .dropFirst)
        #expect(ways.first?.steps.map(\.kind) == [.dropLuggage, .rest, .checkIn, .next])
    }

    @Test func theRestWaitsForCheckInAndTheRoomFillsTheTimeUntilDinner() async throws {
        let ways = await ActionScene.build(
            input([.tired, .heavyLuggage]), search: search, walking: walking, luggageCheck: { _ in .official }
        )
        let way = try #require(ways.first)
        let checkIn = try #require(way.steps.first { $0.kind == .checkIn })
        #expect(checkIn.startMinutes == 15 * 60)
        let last = try #require(way.steps.last)
        // The next plan is reached the margin before it starts, and the sit time is the rest plus the room.
        #expect(last.arriveMinutes == 17 * 60 - ActionGap.marginMinutes)
        #expect(way.slackMinutes == ActionGap.marginMinutes)
        let rest = try #require(way.steps.first { $0.kind == .rest })
        let seated = (rest.leaveMinutes - rest.startMinutes) + (checkIn.leaveMinutes - checkIn.startMinutes)
        #expect(way.sitMinutes == seated)
        #expect(rest.leaveMinutes + checkIn.walkBeforeMinutes <= 15 * 60 + 1)
    }

    @Test func aLockerIsAlwaysUnknownAndNeverFirst() async {
        let ways = await ActionScene.build(
            input([.tired, .heavyLuggage]), search: search, walking: walking, luggageCheck: { _ in .official }
        )
        let locker = ways.first { $0.reason == .locker }
        #expect(locker?.hasUnknown == true)
        #expect(ways.first?.reason != .locker)
    }

    @Test func withoutLuggageThereIsNoDropOrLocker() async {
        let ways = await ActionScene.build(input([.tired]), search: search, walking: walking)
        #expect(!ways.isEmpty)
        #expect(ways.allSatisfy { way in !way.steps.contains { [.dropLuggage, .lockerDrop].contains($0.kind) } })
    }

    @Test func veryTiredAddsOnlyOnePlace() async {
        let ways = await ActionScene.build(
            input([.tired, .heavyLuggage], strength: .very), search: search, walking: walking
        )
        #expect(!ways.isEmpty)
        #expect(ways.allSatisfy { $0.addedPlaces <= 1 })
        #expect(!ways.contains { $0.reason == .locker })
    }

    @Test func cannotWalkRestsOnlyNearHere() async {
        let ways = await ActionScene.build(
            input([.tired, .heavyLuggage], strength: .cannotWalk), search: search, walking: walking
        )
        let rests = ways.flatMap(\.steps).filter { $0.kind == .rest }.map(\.title)
        #expect(!rests.isEmpty)
        #expect(!rests.contains("宿のそばのカフェ"))
    }

    @Test func hungryLooksForAPlaceToEat() async {
        let ways = await ActionScene.build(input([.hungry]), search: search, walking: walking)
        #expect(ways.first?.steps.first?.kind == .eat)
        #expect(ways.first?.steps.first?.title == "食堂")
    }

    @Test func aStayAlreadyOpenIsEnteredNow() async {
        let ways = await ActionScene.build(input([.tired], now: 15 * 60 + 30), search: search, walking: walking)
        #expect(ways.map(\.reason) == [.stayNow])
        #expect(ways.first?.steps.first?.startMinutes == ways.first?.steps.first?.arriveMinutes)
    }

    @Test func aWayThatCannotReachDinnerIsKeptBehindTheOnesThatCan() {
        func way(_ reason: SceneWay.Reason, slack: Int, unknown: Bool = false) -> SceneWay {
            let step = SceneStep(
                kind: .rest, title: "", place: origin, walkBeforeMinutes: 0, arriveMinutes: 0, startMinutes: 0,
                leaveMinutes: 0, isUnknown: unknown
            )
            return SceneWay(
                reason: reason, steps: [step], walkMinutes: 10, sitMinutes: 60, slackMinutes: slack, carryMinutes: 0
            )
        }
        let ordered = ActionScene.order([way(.otherSeat, slack: -5), way(.leastWalk, slack: 15)], heavyLuggage: false)
        #expect(ordered.map(\.reason) == [.leastWalk, .otherSeat])
        let unknownFirst = ActionScene.order(
            [way(.dropIfAllowed, slack: 15, unknown: true), way(.leastWalk, slack: 15)], heavyLuggage: true
        )
        #expect(unknownFirst.first?.reason == .leastWalk)
    }
}
