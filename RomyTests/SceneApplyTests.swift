import Foundation
@testable import Romy
import SwiftData
import Testing

@MainActor
struct SceneApplyTests {
    private let station = ProposalPlace(name: "京都駅", latitude: 34.985, longitude: 135.758)
    private let cafe = ProposalPlace(name: "カフェ", category: "cafe", latitude: 34.987, longitude: 135.759)
    private let hotelPlace = ProposalPlace(name: "宿", latitude: 34.988, longitude: 135.760)

    private struct Day {
        let context: ModelContext
        let trip: Trip
        let plans: [ItineraryItem]
    }

    private func makeDay() throws -> Day {
        let container = try ModelContainer(
            for: Trip.self, ItineraryItem.self, WishPlace.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let trip = Trip(name: "京都旅行", isNameAuto: true, destinations: [], dates: .days(2))
        context.insert(trip)
        let now = ItineraryItem(title: "東本願寺", day: 1, order: 0, kind: .sight, latitude: 34.991, longitude: 135.758)
        now.durationMinutes = 90
        let museum = ItineraryItem(title: "博物館", day: 1, order: 1, kind: .sight, latitude: 34.99, longitude: 135.77)
        let hotel = ItineraryItem(title: "宿", day: 1, order: 2, kind: .stay, latitude: 34.988, longitude: 135.760)
        hotel.notBeforeMinutes = 900
        let dinner = ItineraryItem(title: "お店", day: 1, order: 3, kind: .food, latitude: 34.986, longitude: 135.757)
        dinner.fixedStartMinutes = 1020
        let undecided = ItineraryItem(title: "あとで", day: nil, order: 0, kind: .sight)
        for item in [now, museum, hotel, dinner, undecided] {
            context.insert(item)
            item.trip = trip
        }
        return Day(context: context, trip: trip, plans: [now, museum, hotel, dinner, undecided])
    }

    private func step(
        _ kind: SceneStep.Kind, _ title: String, _ place: ProposalPlace, _ start: Int, _ leave: Int,
        unknown: Bool = false
    ) -> SceneStep {
        SceneStep(kind: kind, title: title, place: place, walkBeforeMinutes: 4, arriveMinutes: start,
                  startMinutes: start, leaveMinutes: leave, isUnknown: unknown)
    }

    private func luggageWay(slack: Int = 10) -> SceneWay {
        SceneWay(
            reason: .dropIfAllowed,
            steps: [
                step(.dropLuggage, "宿", hotelPlace, 848, 853, unknown: true),
                step(.rest, "カフェ", cafe, 856, 897),
                step(.checkIn, "宿", hotelPlace, 900, 1000),
                step(.next, "お店", station, 1010, 1010)
            ],
            walkMinutes: 16, sitMinutes: 141, slackMinutes: slack, carryMinutes: 8
        )
    }

    private func request(_ trip: Trip, current: ItineraryItem) -> SceneRequest {
        SceneRequest(
            id: current.id, plans: trip.items(on: 1).map { $0.snapshot() }, states: [.tired, .heavyLuggage],
            strength: .quite, currentStartMinutes: 780
        )
    }

    @Test func onlyTheNewStepsAreAddedRightAfterNowAndTheStayAndFixedPlanStay() throws {
        let day = try makeDay()
        let (context, trip, plans) = (day.context, day.trip, day.plans)
        let change = try SceneApply.make(
            way: luggageWay(), request: request(trip, current: plans[0]), searchedAtMinutes: 840, nowMinutes: 842
        ).get()
        #expect(trip.items(on: 1).count == 4)

        let (added, _) = trip.apply(change)
        for item in added {
            context.insert(item)
            item.trip = trip
        }
        #expect(trip.items(on: 1).map(\.title) == ["東本願寺", "宿に荷物を預ける", "カフェで休む", "宿", "お店"])
        #expect(added.map(\.kind) == [.other, .food])
        #expect(added.map(\.durationMinutes) == [5, 41])
        #expect(added.allSatisfy { $0.travelMode == .walking && $0.doneAt == nil })
        #expect(plans[0].durationMinutes == 60)
        #expect(plans[0].doneAt == nil)
        #expect(plans[2].notBeforeMinutes == 900)
        #expect(plans[3].fixedStartMinutes == 1020)
    }

    @Test func aPlanTheWayLeavesOutGoesToUndecidedAndIsCounted() throws {
        let day = try makeDay()
        let (trip, plans) = (day.trip, day.plans)
        let change = try SceneApply.make(
            way: luggageWay(), request: request(trip, current: plans[0]), searchedAtMinutes: 840, nowMinutes: 840
        ).get()
        #expect(change.skipped.map(\.title) == ["博物館"])
        #expect(change.message == "2件を旅程に追加しました（1件は未定へ）")
        _ = trip.apply(change)
        #expect(plans[1].day == nil)
        #expect(trip.items(on: nil).map(\.title) == ["あとで", "博物館"])
    }

    @Test func undoPutsEveryPlanBackWhereItWas() throws {
        let day = try makeDay()
        let (context, trip, plans) = (day.context, day.trip, day.plans)
        let before = trip.items.map { ($0.id, $0.day, $0.order, $0.durationMinutes) }
        let change = try SceneApply.make(
            way: luggageWay(), request: request(trip, current: plans[0]), searchedAtMinutes: 840, nowMinutes: 840
        ).get()
        let (added, positions) = trip.apply(change)
        for item in added {
            context.insert(item)
            item.trip = trip
        }
        for item in added { context.delete(item) }
        trip.restore(positions)
        try context.save()
        let after = trip.items.map { ($0.id, $0.day, $0.order, $0.durationMinutes) }
        #expect(after.count == before.count)
        for old in before {
            let new = try #require(after.first { $0.0 == old.0 })
            #expect(new.1 == old.1 && new.2 == old.2 && new.3 == old.3)
        }
    }

    @Test func anItineraryChangedAfterTheSearchIsNotOverwritten() throws {
        let day = try makeDay()
        let (trip, plans) = (day.trip, day.plans)
        let change = try SceneApply.make(
            way: luggageWay(), request: request(trip, current: plans[0]), searchedAtMinutes: 840, nowMinutes: 840
        ).get()
        #expect(change.matches(trip.items(on: 1).map { $0.snapshot() }))
        plans[3].fixedStartMinutes = 1050
        #expect(!change.matches(trip.items(on: 1).map { $0.snapshot() }))
    }

    @Test func aWayThatIsLateOrOldIsNotPutIn() throws {
        let day = try makeDay()
        let (trip, plans) = (day.trip, day.plans)
        let late = SceneApply.make(
            way: luggageWay(slack: -5), request: request(trip, current: plans[0]), searchedAtMinutes: 840,
            nowMinutes: 840
        )
        #expect(throws: SceneApply.Problem.doesNotFit) { try late.get() }
        let old = SceneApply.make(
            way: luggageWay(), request: request(trip, current: plans[0]), searchedAtMinutes: 840,
            nowMinutes: 840 + SceneApply.freshMinutes + 1
        )
        #expect(throws: SceneApply.Problem.tooLate) { try old.get() }
    }
}
