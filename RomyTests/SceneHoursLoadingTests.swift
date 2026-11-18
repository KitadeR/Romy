import MapKit
import Testing
@testable import Romy

@MainActor
struct SceneHoursLoadingTests {
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func checkingEndsOnBothSuccessAndFailureWithoutReplacingTheOption(succeeds: Bool) async throws {
        let cafe = ProposalPlace(name: "喫茶店", latitude: 35, longitude: 135)
        let date = Date()
        var pending: CheckedContinuation<SceneHours?, Never>?
        let model = ActionSceneModel(
            request: SceneRequest(id: UUID(), plans: [], states: [.wantSit], strength: nil,
                                  freeDay: 1, searchDate: date),
            routes: SceneRoutes { _, _ in SceneRoute(minutes: 4, polyline: MKPolyline()) },
            search: { _ in [cafe] },
            ai: SceneAI(interpret: { _, _ in nil }, hours: { _, _, _ in
                await withCheckedContinuation { pending = $0 }
            })
        )
        await model.refresh(origin: cafe, nowMinutes: 600, usesPlanPlace: false)
        let option = try #require(model.ways.first)
        #expect(!model.isCheckingHours(for: option))
        let task = Task { await model.checkHours(for: option) }
        while pending == nil { await Task.yield() }
        #expect(model.isCheckingHours(for: option))
        #expect(model.ways.first?.way == option.way)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fact = SceneHours(status: "official", date: formatter.string(from: date),
                              timeZone: TimeZone.current.identifier,
                              windows: [.init(start: 540, end: 1080, lastOrder: nil)], closed: false,
                              sources: [.init(url: "https://example.com", title: "公式", official: true)],
                              checkedAt: ISO8601DateFormatter().string(from: date))
        pending?.resume(returning: succeeds ? fact : nil)
        await task.value
        #expect(!model.isCheckingHours(for: option))
        #expect(model.checkingHours.isEmpty)
        #expect((model.hours[cafe.scenePlaceKey] != nil) == succeeds)
        #expect(model.ways.first?.way == option.way)
    }
}
