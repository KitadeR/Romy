import Foundation
import MapKit
import Testing
@testable import Romy

/// The stay's luggage check (Notion 02 §6-4「決定（2026-10-29）｜事実の確認⑤」「Figma 23 2版」).
@MainActor
struct LuggageFactTests {
    private let checkedAt = ISO8601DateFormatter().date(from: "2026-10-28T03:00:00Z")!

    private func fact(_ status: String, locker: String = "unknown", key: String = "id:I1") -> LuggageFact {
        LuggageFact(
            status: status, conditions: status == "official" ? ["当日の朝から"] : [],
            sources: [.init(url: "https://hotel.example.jp/faq", title: "FAQ", official: true)],
            locker: locker, foundName: "ホテル", checkedAt: checkedAt, placeKey: key
        )
    }

    // MARK: The relay's answer

    @Test func readsTheRelaysAnswerAndKeepsItsDate() throws {
        let json = """
        {"status":"official","conditions":["当日の朝から"],
         "sources":[{"url":"https://a.jp/faq","title":"FAQ","official":true}], "locker":"no",
         "foundName":"ホテル","checkedAt":"2026-10-28T16:10:00.651Z","cached":true}
        """
        let fact = try #require(FactRelay.decode(Data(json.utf8)))
        #expect(fact.result == .official)
        #expect(fact.conditions == ["当日の朝から"])
        #expect(fact.sources.first?.official == true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(fact.checkedDateText(calendar: calendar) == "10/29 確認")
    }

    @Test func thePublishedRelayIsReadFromItsFileAndAHalfWrittenOneIsIgnored() throws {
        func plist(_ url: String, _ token: String) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: ["URL": url, "Token": token], format: .xml, options: 0)
        }
        let config = RelayConfig.decode(try plist("https://romy-relay.example.workers.dev", "secret"))
        #expect(config?.url.host() == "romy-relay.example.workers.dev")
        #expect(config?.token == "secret")
        #expect(RelayConfig.decode(try plist("https://romy-relay.example.workers.dev", "")) == nil)
        #expect(RelayConfig.decode(try plist("http://romy-relay.example.workers.dev", "secret")) == nil)
        #expect(RelayConfig.decode(Data("not a plist".utf8)) == nil)
    }

    @Test func anAnswerWithAReasonIsNotKept() {
        let json = """
        {"status":"unknown","conditions":[],"sources":[],"locker":"unknown","checkedAt":"2026-10-28T16:10:00.651Z",
         "cached":false,"reason":"limit"}
        """
        #expect(FactRelay.decode(Data(json.utf8)) == nil)
    }

    @Test func yesAndNoLastThirtyDaysAndTheRestThree() {
        let day: TimeInterval = 86_400
        #expect(fact("official").isFresh(at: checkedAt.addingTimeInterval(29 * day)))
        #expect(!fact("official").isFresh(at: checkedAt.addingTimeInterval(31 * day)))
        #expect(fact("contradicted").isFresh(at: checkedAt.addingTimeInterval(29 * day)))
        #expect(!fact("unknown").isFresh(at: checkedAt.addingTimeInterval(4 * day)))
        #expect(!fact("introduced").isFresh(at: checkedAt.addingTimeInterval(4 * day)))
    }

    @Test func eachResultHasItsLine() {
        #expect(fact("official").caption == "✓ チェックイン前も預けられる（公式）")
        #expect(fact("contradicted").caption == "✗ この宿はチェックイン前の預かりがありません")
        #expect(fact("unknown", locker: "yes").caption == "宿のロッカーあり（空きは分かりません）")
        #expect(fact("unknown").caption == "？ 宿で預けられるかは未確認です")
    }

    // MARK: Checking ahead

    private func stay(
        day: Int, kind: StayKind? = .hotel, latitude: Double? = 35, fact: LuggageFact? = nil
    ) -> LuggagePrefetch.Stay {
        LuggagePrefetch.Stay(
            id: UUID(), title: "ホテル", placeID: "I1", area: "下京区", latitude: latitude,
            checkInDate: checkedAt.addingTimeInterval(Double(day) * 86_400), stayKind: kind, fact: fact
        )
    }

    @Test func checksAheadOnlyTheStaysOfTodayAndTomorrow() {
        let now = checkedAt
        let due = LuggagePrefetch.due([stay(day: 0), stay(day: 1), stay(day: 2), stay(day: -1)], now: now)
        #expect(due.count == 2)
    }

    @Test func doesNotCheckAFriendsHouseAPlaceLessStayOrAFreshCheck() {
        let now = checkedAt
        #expect(LuggagePrefetch.due([stay(day: 1, kind: .friend)], now: now).isEmpty)
        #expect(LuggagePrefetch.due([stay(day: 1, latitude: nil)], now: now).isEmpty)
        #expect(LuggagePrefetch.due([stay(day: 1, fact: fact("official"))], now: now).isEmpty)
        // The stay's place changed since it was checked.
        #expect(LuggagePrefetch.due([stay(day: 1, fact: fact("official", key: "id:OTHER"))], now: now).count == 1)
    }

    // MARK: Romy Now

    private var way: SceneWay {
        let place = ProposalPlace(name: "ホテル", latitude: 35, longitude: 135)
        let drop = SceneStep(
            kind: .dropLuggage, title: "ホテル", place: place, walkBeforeMinutes: 5, arriveMinutes: 845,
            startMinutes: 845, leaveMinutes: 850, isUnknown: true
        )
        return SceneWay(
            reason: .dropIfAllowed, steps: [drop], walkMinutes: 5, sitMinutes: 100, slackMinutes: 10, carryMinutes: 0
        )
    }

    @Test func aYesChangesTheHeadlineAndTheMarkButNotTheTimes() {
        let option = SceneOption(id: "B", way: way, luggage: .checking).answered(fact("official"))
        #expect(option.way.reason == .dropFirst)
        #expect(option.way.hasUnknown == false)
        #expect(option.way.sitMinutes == 100)
        #expect(option.luggageCaption == "✓ チェックイン前も預けられる（公式）")
        #expect(!option.isUnavailable)
    }

    @Test func aNoDimsTheWayAndNothingBackLeavesItUnknown() {
        let refused = SceneOption(id: "B", way: way, luggage: .checking).answered(fact("contradicted"))
        #expect(refused.isUnavailable)
        #expect(refused.way.reason == .dropIfAllowed)
        let nothing = SceneOption(id: "B", way: way, luggage: .checking).answered(nil)
        #expect(nothing.luggage == .none)
        #expect(!nothing.isUnavailable)
    }

    private func request() -> (SceneRequest, ItineraryItem) {
        let current = ItineraryItem(title: "今", day: 1, order: 0, kind: .sight, latitude: 35, longitude: 135)
        let hotel = ItineraryItem(
            title: "ホテル", day: 1, order: 1, kind: .stay, latitude: 35, longitude: 135.006, placeID: "I1"
        )
        hotel.notBeforeMinutes = 15 * 60
        let dinner = ItineraryItem(title: "お店", day: 1, order: 2, kind: .food, latitude: 35.002, longitude: 135.009)
        dinner.fixedStartMinutes = 17 * 60
        let request = SceneRequest(
            id: current.id, plans: [current.snapshot(), hotel.snapshot(), dinner.snapshot()],
            states: [.tired, .heavyLuggage], strength: .quite
        )
        return (request, hotel)
    }

    private var here: ProposalPlace { ProposalPlace(name: "今", latitude: 35, longitude: 135) }
    private var routes: SceneRoutes { SceneRoutes { _, _ in SceneRoute(minutes: 4, polyline: MKPolyline()) } }
    private var search: CandidateSearch {
        { query in
            query.text == "カフェ" ? [ProposalPlace(name: "宿のそばのカフェ", latitude: 35.0005, longitude: 135.0065)] : []
        }
    }

    @Test func romyNowAsksWhenNothingIsKeptAndSavesTheAnswer() async throws {
        let (request, hotel) = request()
        var saved: [UUID: LuggageFact] = [:]
        let answer = fact("official")
        let facts = LuggageFacts(
            stored: { _ in nil }, check: { _ in answer }, save: { saved[$0] = $1 }, allowed: { true }
        )
        let model = ActionSceneModel(
            request: request, routes: routes, search: search, facts: facts, now: { self.checkedAt }
        )
        await model.refresh(origin: here, nowMinutes: 14 * 60, usesPlanPlace: false)
        let drop = try #require(model.ways.first { $0.way.leavesLuggageAtStay })
        #expect(drop.luggage == .checked(answer))
        #expect(drop.way.reason == .dropFirst)
        #expect(saved[hotel.id] == answer)
        #expect(model.footnote.contains("宿の荷物預かりはAIが調べた公開情報です"))
    }

    @Test func romyNowUsesAKeptCheckWithoutAsking() async throws {
        let (request, _) = request()
        var asked = 0
        let kept = fact("official", key: "id:I1")
        let facts = LuggageFacts(
            stored: { _ in kept }, check: { _ in asked += 1; return nil }, save: { _, _ in }, allowed: { true }
        )
        let model = ActionSceneModel(
            request: request, routes: routes, search: search, facts: facts, now: { self.checkedAt }
        )
        await model.refresh(origin: here, nowMinutes: 14 * 60, usesPlanPlace: false)
        #expect(asked == 0)
        #expect(model.ways.first?.way.reason == .dropFirst)
    }

    @Test func withoutTheAnswerToTheSheetNothingIsAsked() async {
        let (request, _) = request()
        var asked = 0
        let facts = LuggageFacts(
            stored: { _ in nil }, check: { _ in asked += 1; return nil }, save: { _, _ in }, allowed: { false }
        )
        let model = ActionSceneModel(request: request, routes: routes, search: search, facts: facts)
        await model.refresh(origin: here, nowMinutes: 14 * 60, usesPlanPlace: false)
        #expect(asked == 0)
        #expect(model.ways.allSatisfy { $0.luggage == .none })
        #expect(model.footnote.contains("荷物預かり・ロッカーや席の空き・営業時間は確認していません"))
    }
}
