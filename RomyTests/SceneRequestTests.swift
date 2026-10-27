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

    @Test func theStayAndTheFixedPlanAfterItAreBothTakenFromTheItinerary() throws {
        let now = plan("今の予定", order: 0)
        let hotel = plan("宿", order: 1, kind: .stay)
        hotel.notBeforeMinutes = 900
        let dinner = plan("予約", order: 2, fixed: 1020)
        let request = SceneRequest(id: now.id, plans: [now, hotel, dinner].map { $0.snapshot() },
                                   states: [.tired, .heavyLuggage], strength: .quite)
        let result = try request.input(origin: request.currentPlace, nowMinutes: 840).get()
        #expect(result.stay?.checkInMinutes == 900)
        #expect(result.nextTitle == "予約")
        #expect(result.nextStartMinutes == 1020)
        #expect(result.hasHeavyLuggage)
        #expect(result.strength == .quite)
    }

    @Test func aFixedPlanWithoutAPlaceIsNotSilentlySkipped() {
        let now = plan("今", order: 0)
        let first = plan("最初の予約", order: 1, fixed: 900)
        first.latitude = nil
        let later = plan("後の予約", order: 2, fixed: 1020)
        let request = SceneRequest(
            id: now.id,
            plans: [now, first, later].map { $0.snapshot() },
            states: [.hungry],
            strength: nil
        )
        #expect(throws: SceneRequest.Issue.needsNextPlace) {
            try request.input(origin: request.currentPlace, nowMinutes: 840).get()
        }
    }

    @Test func anUnknownCheckInIsNotTreatedAsOpenNow() {
        let now = plan("今", order: 0)
        let hotel = plan("宿", order: 1, kind: .stay)
        let dinner = plan("予約", order: 2, fixed: 1020)
        let request = SceneRequest(
            id: now.id,
            plans: [now, hotel, dinner].map { $0.snapshot() },
            states: [.tired],
            strength: .quite
        )
        #expect(throws: SceneRequest.Issue.needsCheckIn) {
            try request.input(origin: request.currentPlace, nowMinutes: 840).get()
        }
    }

    @Test func aGuessedTimeIsNotUsedAsAFixedDeadlineAndMissingLocationIsExplicit() {
        let now = plan("今", order: 0)
        let later = plan("目安だけの予定", order: 1)
        let request = SceneRequest(
            id: now.id,
            plans: [now, later].map { $0.snapshot() },
            states: [.hungry],
            strength: nil
        )
        #expect(throws: SceneRequest.Issue.needsFixedPlan) {
            try request.input(origin: request.currentPlace, nowMinutes: 840).get()
        }
        #expect(throws: SceneRequest.Issue.needsLocation) { try request.input(origin: nil, nowMinutes: 840).get() }
    }

    @Test func changingTheItineraryDoesNotMutateTheSearchSnapshot() throws {
        let now = plan("今", order: 0)
        let next = plan("予約", order: 1, fixed: 1020)
        let request = SceneRequest(
            id: now.id,
            plans: [now, next].map { $0.snapshot() },
            states: [.hungry],
            strength: .very
        )
        next.fixedStartMinutes = 900
        let input = try request.input(origin: request.currentPlace, nowMinutes: 840).get()
        #expect(input.nextStartMinutes == 1020)
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
