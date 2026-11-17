import Foundation
import MapKit
import SwiftData
import Testing
@testable import Romy

@MainActor
struct SceneEnhancementTests {
    private let origin = ProposalPlace(name: "神戸電子専門学校", latitude: 34.699, longitude: 135.191)
    private let cafe = ProposalPlace(name: "喫茶店", address: "神戸市中央区1-1", latitude: 34.6995, longitude: 135.191)

    private func request(note: String = "") -> SceneRequest {
        SceneRequest(id: UUID(), plans: [], states: [.wantSit], strength: nil, freeDay: 1, note: note)
    }
    private var routes: SceneRoutes {
        SceneRoutes { _, _ in SceneRoute(minutes: 4, polyline: MKPolyline()) }
    }

    @Test func emptyDayCreatesRealPlansAtTheSearchedTimeAndCanBeUndone() async throws {
        let container = try ModelContainer(for: Trip.self, ItineraryItem.self, WishPlace.self,
                                         configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let trip = Trip(name: "神戸旅行", isNameAuto: false, destinations: [], dates: .days(1))
        context.insert(trip)
        let request = request()
        let input = try request.input(origin: origin, nowMinutes: 840, chosenMinutes: 60).get()
        let ways = await ActionScene.build(input, search: { _ in [cafe] }, walking: { _, _ in 4 })
        let change = try SceneApply.make(way: #require(ways.first), request: request,
                                        searchedAtMinutes: 840, nowMinutes: 841).get()
        #expect(change.currentID == nil)
        #expect(change.skipped.isEmpty)
        let result = trip.apply(change)
        for plan in result.added { context.insert(plan); plan.trip = trip }
        try context.save()
        #expect(trip.items(on: 1).first?.fixedStartMinutes == 844)
        #expect(trip.items(on: 1).first?.durationMinutes == 56)
        trip.restore(result.before)
        for plan in result.added { context.delete(plan) }
        try context.save()
        #expect(trip.items(on: 1).isEmpty)
    }

    @Test func allDonePlansAreKeptAndNotMadeIntoAnArtificialCurrentPlan() throws {
        let done = ItineraryItem(title: "学校", day: 1, order: 0, kind: .sight)
        done.doneAt = .now
        let request = SceneRequest(id: UUID(), plans: [done.snapshot()], states: [.wantSit], strength: nil, freeDay: 1)
        let input = try request.input(origin: origin, nowMinutes: 840, chosenMinutes: 60).get()
        #expect(request.current == nil)
        #expect(input.end == .chosen)
        #expect(request.ahead(nowMinutes: 840)?.between.isEmpty == true)
    }

    @Test func explicitRestAndTotalAreDifferentAndTheNextFixedPlanIsKept() async throws {
        var input = try request().input(origin: origin, nowMinutes: 840, chosenMinutes: 90).get()
        input.preferences = ScenePreferences(restMinutes: 30, totalMinutes: 60)
        let first = try #require(await ActionScene.build(input, search: { _ in [cafe] }, walking: { _, _ in 4 }).first)
        #expect(first.steps.first?.leaveMinutes == 874)
        #expect(first.sitMinutes == 30)
        input.preferences = ScenePreferences(totalMinutes: 30)
        let total = try #require(await ActionScene.build(input, search: { _ in [cafe] }, walking: { _, _ in 4 }).first)
        #expect(total.steps.last?.leaveMinutes == 870)
        #expect(total.sitMinutes == 26)
        let fixed = SceneInput(nowMinutes: 840, origin: origin, stay: nil,
                               end: .plan(title: "予約", place: cafe), endMinutes: 870, states: [.wantSit], strength: nil,
                               preferences: ScenePreferences(restMinutes: 30, totalMinutes: 120))
        let late = try #require(await ActionScene.build(fixed, search: { _ in [cafe] }, walking: { _, _ in 4 }).first)
        #expect(late.steps.last?.kind == .next)
        #expect(!late.fits)
    }

    @Test func aWalkingLimitUsesTheRealRouteRatherThanOnlyTheRadius() async throws {
        var input = try request().input(origin: origin, nowMinutes: 840, chosenMinutes: 60).get()
        input.preferences = ScenePreferences(walkMinutes: 3)
        #expect(await ActionScene.build(input, search: { _ in [cafe] }, walking: { _, _ in 9 }).isEmpty)
    }

    @Test func refinementSkipsSeenShopsWithoutSendingTheNoteAgainAndKeepsResultsOnFailure() async throws {
        var interpretations = 0
        var returnsEmpty = false
        let other = ProposalPlace(name: "別の喫茶店", latitude: 34.6998, longitude: 135.191)
        let third = ProposalPlace(name: "新しい喫茶店", latitude: 34.700, longitude: 135.191)
        let ai = SceneAI(interpret: { _, _ in interpretations += 1; return ScenePreferences(restMinutes: 30) },
                         hours: { _, _, _ in nil })
        let model = ActionSceneModel(request: request(note: "30分休む"), routes: routes,
                                     search: { _ in returnsEmpty ? [] : [cafe, other, third] }, ai: ai)
        await model.refresh(origin: origin, nowMinutes: 840, usesPlanPlace: false)
        let seen = Set(model.ways.flatMap { $0.way.steps.map(\.place.name) })
        await model.refresh(origin: origin, nowMinutes: 841, usesPlanPlace: false, refinement: .others)
        #expect(!model.ways.isEmpty)
        #expect(model.ways.allSatisfy { !seen.contains($0.way.steps[0].place.name) })
        #expect(interpretations == 1)
        let kept = model.ways.map(\.way)
        returnsEmpty = true
        await model.refresh(origin: origin, nowMinutes: 842, usesPlanPlace: false, refinement: .closer)
        #expect(model.ways.map(\.way) == kept)
        #expect(model.refinementMessage != nil)
        #expect(!model.isRefining)
    }

    @Test func officialHoursCoverArrivalDepartureAndLastOrderAndExpire() {
        let target = Date()
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let iso = ISO8601DateFormatter()
        let fact = SceneHours(status: "official", date: formatter.string(from: target), timeZone: TimeZone.current.identifier,
                              windows: [.init(start: 600, end: 1200, lastOrder: 1140)], closed: false,
                              sources: [.init(url: "https://example.jp/kobe", title: "公式", official: true)],
                              checkedAt: iso.string(from: target))
        func step(_ start: Int, _ end: Int) -> SceneStep {
            SceneStep(kind: .rest, title: cafe.name, place: cafe, walkBeforeMinutes: 4,
                      arriveMinutes: start, startMinutes: start, leaveMinutes: end, isUnknown: false)
        }
        #expect(fact.isFresh(on: target, at: target))
        #expect(fact.permits(step(1100, 1200)))
        #expect(!fact.permits(step(1141, 1200)))
        #expect(!fact.permits(step(1100, 1201)))
        #expect(!fact.isFresh(on: target, at: target.addingTimeInterval(3601)))
        #expect(!fact.isFresh(on: target.addingTimeInterval(86400), at: target))
    }

    @Test func openingDetailsChecksOnceAndDoesNotReorderOrReplaceTheCard() async throws {
        var calls = 0
        let model = ActionSceneModel(request: request(), routes: routes, search: { _ in [cafe] },
                                     ai: SceneAI(interpret: { _, _ in nil }, hours: { _, _, _ in calls += 1; return nil }))
        await model.refresh(origin: origin, nowMinutes: 840, usesPlanPlace: false)
        let option = try #require(model.ways.first)
        await model.checkHours(for: option)
        await model.checkHours(for: option)
        #expect(calls == 1)
        #expect(model.ways.first?.way == option.way)
        #expect(model.hoursPermit(option))
    }
    @Test func changingStatesWhileInterpretingDoesNotSendTheSameNoteTwice() async {
        var calls = 0
        let ai = SceneAI(interpret: { _, _ in
            calls += 1
            try? await Task.sleep(for: .milliseconds(30))
            return ScenePreferences(restMinutes: 30)
        }, hours: { _, _, _ in nil })
        let model = ActionSceneModel(request: request(note: "30分休む"), routes: routes,
                                     search: { _ in [cafe] }, ai: ai)
        // 位置が分かるまでは送信せず、画面のtaskが作り直されても一度だけ解釈する。
        await model.refresh(origin: nil, nowMinutes: 840, usesPlanPlace: false)
        #expect(calls == 0)
        let first = Task { await model.refresh(origin: origin, nowMinutes: 840, usesPlanPlace: false) }
        while calls == 0 { await Task.yield() }
        model.edit(states: [.hungry], strength: nil)
        await model.refresh(origin: origin, nowMinutes: 841, usesPlanPlace: false)
        await first.value
        #expect(calls == 1)
        #expect(model.input?.states == [.hungry])
        #expect(model.preferences.restMinutes == 30)
    }

    @Test func officialClosurePreventsConfirmationWithoutChangingTheRoute() async throws {
        let date = Date()
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let closed = SceneHours(status: "official", date: formatter.string(from: date), timeZone: TimeZone.current.identifier,
                                windows: [], closed: true,
                                sources: [.init(url: "https://example.jp/kobe", title: "休業案内", official: true)],
                                checkedAt: ISO8601DateFormatter().string(from: date))
        let model = ActionSceneModel(request: request(), routes: routes, search: { _ in [cafe] },
                                     ai: SceneAI(interpret: { _, _ in nil }, hours: { _, _, _ in closed }))
        await model.refresh(origin: origin, nowMinutes: 840, usesPlanPlace: false)
        let option = try #require(model.ways.first)
        await model.checkHours(for: option)
        #expect(!model.hoursPermit(option))
        #expect(model.ways.first?.way == option.way)
    }

    @Test func explicitTotalReplacesTheDefaultLengthOnlyWhenThereIsNoFixedPlan() async {
        let model = ActionSceneModel(request: request(note: "2時間使える"), routes: routes, search: { _ in [cafe] },
                                     ai: SceneAI(interpret: { _, _ in ScenePreferences(totalMinutes: 120) },
                                                 hours: { _, _, _ in nil }))
        await model.refresh(origin: origin, nowMinutes: 840, usesPlanPlace: false)
        #expect(model.chosenMinutes == 90)
        #expect(model.input?.endMinutes == 960)
        #expect(model.ways.first?.way.steps.last?.leaveMinutes == 960)
    }

    @Test func aSpecificFoodWishIsNotSilentlyReplacedWithAnyCafe() async throws {
        var queries: [String] = []
        var input = try request().input(origin: origin, nowMinutes: 840, chosenMinutes: 60).get()
        input.preferences = ScenePreferences(query: "パンケーキ", category: "cafe")
        let ways = await ActionScene.build(input, search: { query in
            queries.append(query.text)
            return query.text == "カフェ" ? [cafe] : []
        }, walking: { _, _ in 4 })
        #expect(ways.isEmpty)
        #expect(!queries.contains("カフェ"))
    }

}
