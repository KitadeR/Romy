import Foundation
import MapKit
@testable import Romy
import Testing

@MainActor
struct SceneRequestTests {
    private func plan(_ name: String, order: Int, kind: PlanKind = .sight, fixed: Int? = nil) -> ItineraryItem {
        let item = ItineraryItem(title: name, day: 1, order: order, kind: kind, latitude: 34.986, longitude: 135.758)
        item.fixedStartMinutes = fixed
        return item
    }

    private func request(
        _ plans: [ItineraryItem], states: Set<ActionState> = [.tired], strength: TiredStrength? = .quite
    ) -> SceneRequest {
        SceneRequest(id: plans[0].id, plans: plans.map { $0.snapshot() }, states: states, strength: strength)
    }

    @Test func theStayAndTheFixedPlanAfterItAreBothTakenFromTheItinerary() throws {
        let now = plan("今の予定", order: 0)
        let hotel = plan("宿", order: 1, kind: .stay)
        hotel.notBeforeMinutes = 900
        let dinner = plan("予約", order: 2, fixed: 1020)
        let request = request([now, hotel, dinner], states: [.tired, .heavyLuggage])
        let result = try request.input(origin: request.currentPlace, nowMinutes: 840, chosenMinutes: 90).get()
        #expect(result.stay?.checkInMinutes == 900)
        #expect(result.next?.title == "予約")
        #expect(result.endMinutes == 1020)
        #expect(result.hasHeavyLuggage)
        #expect(result.strength == .quite)
    }

    @Test func aFixedPlanWithoutAPlaceStillEndsTheTimeAndIsNotSkipped() throws {
        let now = plan("今", order: 0)
        let first = plan("最初の予約", order: 1, fixed: 900)
        first.latitude = nil
        let later = plan("後の予約", order: 2, fixed: 1020)
        let request = request([now, first, later], states: [.hungry], strength: nil)
        let result = try request.input(origin: request.currentPlace, nowMinutes: 840, chosenMinutes: 90).get()
        #expect(result.end == .plan(title: "最初の予約", place: nil))
        #expect(result.endMinutes == 900)
        #expect(result.next == nil)
    }

    @Test func withoutAFixedPlanTheStaysCheckInEndsTheTime() throws {
        let now = plan("今", order: 0)
        let hotel = plan("宿", order: 1, kind: .stay)
        hotel.notBeforeMinutes = 900
        let later = plan("目安だけの予定", order: 2)
        let request = request([now, hotel, later], states: [.heavyLuggage])
        let result = try request.input(origin: request.currentPlace, nowMinutes: 840, chosenMinutes: 90).get()
        #expect(result.end == .checkIn)
        #expect(result.endMinutes == 900)
        #expect(result.stay?.title == "宿")
        // The plan after the stay is left where it is.
        #expect(request.ahead(nowMinutes: 840)?.between.isEmpty == true)
    }

    @Test func withNothingToEndTheTimeTheChosenLengthIsUsedAndATimeIsNeverGuessed() throws {
        let now = plan("今", order: 0)
        let later = plan("目安だけの予定", order: 1)
        let unknownCheckIn = plan("宿", order: 2, kind: .stay)
        let request = request([now, later, unknownCheckIn], states: [.hungry], strength: nil)
        let result = try request.input(origin: request.currentPlace, nowMinutes: 840, chosenMinutes: 120).get()
        #expect(result.end == .chosen)
        #expect(result.endMinutes == 960)
        #expect(result.stay == nil)
        #expect(request.ahead(nowMinutes: 840)?.between.isEmpty == true)
        #expect(throws: SceneRequest.Issue.needsLocation) {
            try request.input(origin: nil, nowMinutes: 840, chosenMinutes: 120).get()
        }
    }

    @Test func aStayAlreadyOpenCanBeEnteredWithinTheChosenLength() throws {
        let now = plan("今", order: 0)
        let hotel = plan("宿", order: 1, kind: .stay)
        hotel.notBeforeMinutes = 780
        let request = request([now, hotel])
        let result = try request.input(origin: request.currentPlace, nowMinutes: 840, chosenMinutes: 90).get()
        #expect(result.end == .chosen)
        #expect(result.stay?.checkInMinutes == 780)
    }

    @Test func changingTheItineraryDoesNotMutateTheSearchSnapshot() throws {
        let now = plan("今", order: 0)
        let next = plan("予約", order: 1, fixed: 1020)
        let request = request([now, next], states: [.hungry], strength: .very)
        next.fixedStartMinutes = 900
        let input = try request.input(origin: request.currentPlace, nowMinutes: 840, chosenMinutes: 90).get()
        #expect(input.endMinutes == 1020)
        #expect(input.strength == nil)
    }

    @Test func directionsAreCachedForTheCoordinatesRatherThanPlaceNames() async {
        var count = 0
        let cache = SceneRoutes { _, _ in
            count += 1
            return SceneRoute(minutes: 8, polyline: MKPolyline())
        }
        let start = ProposalPlace(name: "今", latitude: 35, longitude: 135)
        let end = ProposalPlace(name: "宿", latitude: 35.001, longitude: 135)
        let renamed = ProposalPlace(name: "ホテル", latitude: end.latitude, longitude: end.longitude)
        #expect(await cache.minutes(start, end) == 8)
        #expect(await cache.minutes(start, renamed) == 8)
        #expect(count == 1)
    }
}
