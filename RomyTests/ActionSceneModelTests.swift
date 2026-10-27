import Foundation
import MapKit
import Testing
@testable import Romy

@MainActor
struct ActionSceneModelTests {
    private var origin: ProposalPlace { ProposalPlace(name: "今", latitude: 35, longitude: 135) }

    private func request(states: Set<ActionState> = [.wantSit]) -> SceneRequest {
        let current = ItineraryItem(title: "今", day: 1, order: 0, kind: .sight, latitude: 35, longitude: 135)
        let next = ItineraryItem(title: "予約", day: 1, order: 1, kind: .food, latitude: 35.002, longitude: 135)
        next.fixedStartMinutes = 1020
        return SceneRequest(id: current.id, plans: [current.snapshot(), next.snapshot()], states: states, strength: nil)
    }

    @Test func searchFailureIsDifferentFromFindingNoCandidates() async {
        let empty = ActionSceneModel(request: request(), search: { _ in [] })
        await empty.refresh(origin: origin, nowMinutes: 840, usesPlanPlace: true)
        #expect(empty.phase == .ready)
        #expect(empty.ways.isEmpty)
        #expect(!empty.searchFailed)
        let failed = ActionSceneModel(request: request(), search: { _ in throw URLError(.notConnectedToInternet) })
        await failed.refresh(origin: origin, nowMinutes: 840, usesPlanPlace: false)
        #expect(failed.phase == .ready)
        #expect(failed.ways.isEmpty)
        #expect(failed.searchFailed)
    }

    @Test func aMissingRouteDoesNotBecomeZeroMinutesOrAnEmptySearch() async {
        let routes = SceneRoutes { _, _ in throw URLError(.notConnectedToInternet) }
        let place = ProposalPlace(name: "カフェ", latitude: 35.001, longitude: 135)
        let model = ActionSceneModel(request: request(), routes: routes, search: { _ in [place] })
        await model.refresh(origin: origin, nowMinutes: 840, usesPlanPlace: true)
        #expect(model.ways.isEmpty)
        #expect(model.routeFailed)
        #expect(!model.searchFailed)
    }

    @Test func noStatesDoesNotSearchAndChangingStatesRetainsTheStrength() async {
        var queries = 0
        let model = ActionSceneModel(request: request(states: []), search: { _ in queries += 1; return [] })
        await model.refresh(origin: origin, nowMinutes: 840, usesPlanPlace: false)
        #expect(model.phase == .empty)
        #expect(queries == 0)
        model.edit(states: [.tired, .heavyLuggage], strength: .cannotWalk)
        #expect(model.states == [.tired, .heavyLuggage])
        #expect(model.strength == .cannotWalk)
    }

    @Test func selectionDoesNotChangeTheItineraryAndRefreshClearsSelection() async throws {
        let routes = SceneRoutes { _, _ in SceneRoute(minutes: 3, polyline: MKPolyline()) }
        let place = ProposalPlace(name: "カフェ", latitude: 35.001, longitude: 135)
        let model = ActionSceneModel(request: request(), routes: routes, search: { _ in [place] })
        await model.refresh(origin: origin, nowMinutes: 840, usesPlanPlace: true)
        model.selectedID = try #require(model.ways.first?.id)
        #expect(model.selected != nil)
        #expect(model.request.plans.count == 2)
        #expect(model.request.plans.last?.fixedStartMinutes == 1020)
        await model.refresh(origin: origin, nowMinutes: 850, usesPlanPlace: true)
        #expect(model.selected == nil)
    }
}
