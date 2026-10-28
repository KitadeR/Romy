import Foundation
@testable import Romy
import SwiftData
import Testing

@MainActor
struct PlanHomeGlanceTests {
    private struct Day {
        let context: ModelContext
        let trip: Trip
    }

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))!
    }

    private func makeTrip(destinations: [Destination] = []) throws -> Day {
        let container = try ModelContainer(
            for: Trip.self, ItineraryItem.self, WishPlace.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let trip = Trip(
            name: "京都旅行", isNameAuto: true, destinations: destinations, dates: .range(start: date(9), end: date(11))
        )
        context.insert(trip)
        return Day(context: context, trip: trip)
    }

    @discardableResult
    private func add(
        _ title: String, day: Int?, kind: PlanKind = .sight, fixed: Int? = nil, opens: Int? = nil, to trip: Day
    ) -> ItineraryItem {
        let item = ItineraryItem(title: title, day: day, order: trip.trip.nextOrder(on: day), kind: kind)
        item.fixedStartMinutes = fixed
        item.notBeforeMinutes = opens
        trip.context.insert(item)
        item.trip = trip.trip
        return item
    }

    @Test func theSummaryCountsBookingsAndIsLeftOutWithoutAny() throws {
        let day = try makeTrip()
        add("清水寺", day: 1, to: day)
        #expect(PlanHomeGlance.summary(Preparation(trip: day.trip, now: date(1), calendar: calendar)) == nil)
        add("ホテル", day: 1, kind: .stay, to: day).bookedAt = date(1)
        add("旅館", day: 2, kind: .stay, to: day)
        let summary = PlanHomeGlance.summary(Preparation(trip: day.trip, now: date(1), calendar: calendar))
        #expect(summary == "準備 ・ 予約 2つ中1つ済み")
    }

    @Test func eachDayShowsHowManyPlansItHas() throws {
        let day = try makeTrip()
        add("清水寺", day: 1, to: day)
        add("錦市場", day: 1, to: day)
        add("嵐山", day: 3, to: day)
        add("東京駅", day: nil, to: day)
        let days = ItineraryDays(dates: day.trip.dates, text: DateText(calendar: calendar, holidays: .bundled))
        let counts = PlanHomeGlance.dayCounts(of: day.trip, days: days)
        #expect(counts.map(\.label) == ["11/9", "11/10", "11/11"])
        #expect(counts.map(\.count) == [2, 0, 1])
        day.trip.dates = .days(2)
        let numbered = ItineraryDays(dates: day.trip.dates, text: DateText(calendar: calendar, holidays: .bundled))
        #expect(PlanHomeGlance.dayCounts(of: day.trip, days: numbered).map(\.label) == ["1日目", "2日目"])
        day.trip.dates = .undecided
        let none = ItineraryDays(dates: day.trip.dates, text: DateText(calendar: calendar, holidays: .bundled))
        #expect(PlanHomeGlance.dayCounts(of: day.trip, days: none).isEmpty)
    }

    @Test func theEveShowsTomorrowsFirstPlanThenTheRestWithTheStayAsItOpens() throws {
        let place = Destination(id: "26100", name: "京都市", context: "京都府", kind: .municipality)
        let day = try makeTrip(destinations: [place])
        add("伏見稲荷大社", day: 1, fixed: 630, to: day)
        add("清水寺", day: 1, fixed: 780, to: day)
        add("ホテル", day: 1, kind: .stay, opens: 900, to: day).bookedAt = date(1)
        let eve = PlanHomeGlance.eve(of: day.trip)
        #expect(eve.place == "京都")
        #expect(eve.first?.text == "10:30 伏見稲荷大社")
        #expect(eve.rest.map(\.text) == ["13:00 清水寺", "15:00から ホテル ・ 予約：済み"])
    }

    @Test func anEveWithoutPlansHasNoFirstPlanAndUsesTheTripNameWithoutADestination() throws {
        let day = try makeTrip()
        let eve = PlanHomeGlance.eve(of: day.trip)
        #expect(eve.place == "京都旅行")
        #expect(eve.first == nil)
        #expect(eve.rest.isEmpty)
    }

    @Test func aTripBeingDeletedIsReadAsEmpty() throws {
        let day = try makeTrip()
        add("清水寺", day: 1, to: day)
        day.context.delete(day.trip)
        try day.context.save()
        let eve = PlanHomeGlance.eve(of: day.trip)
        #expect(eve.first == nil)
        #expect(eve.place.isEmpty)
    }

    @Test func theWhiteButtonNamesTheDayOfTheBooking() throws {
        let day = try makeTrip()
        let inn = add("旅館", day: 2, kind: .stay, to: day)
        #expect(PlanHomeGlance.bookTitle(of: inn) == "2日目の宿を予約する")
        inn.stayKind = .later
        #expect(PlanHomeGlance.bookTitle(of: inn) == "2日目の宿を決める")
        #expect(PlanHomeGlance.bookTitle(of: add("祇園", day: 1, to: day)) == "祇園を予約する")
        #expect(PlanHomeGlance.bookTitle(of: add("割烹", day: 1, kind: .food, to: day)) == "1日目のお店を予約する")
    }
}
