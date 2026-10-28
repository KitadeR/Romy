import Foundation
@testable import Romy
import SwiftData
import Testing

@MainActor
struct PreparationTests {
    private struct Day {
        let context: ModelContext
        let trip: Trip
    }

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func makeTrip() throws -> Day {
        let container = try ModelContainer(
            for: Trip.self, ItineraryItem.self, WishPlace.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let trip = Trip(name: "京都旅行", isNameAuto: true, destinations: [], dates: .range(start: date(9), end: date(11)))
        context.insert(trip)
        return Day(context: context, trip: trip)
    }

    @discardableResult
    private func add(
        _ title: String, day: Int?, kind: PlanKind, fixed: Int? = nil, opens: Int? = nil, to trip: Day
    ) -> ItineraryItem {
        let item = ItineraryItem(title: title, day: day, order: trip.trip.nextOrder(on: day), kind: kind)
        item.fixedStartMinutes = fixed
        item.notBeforeMinutes = opens
        trip.context.insert(item)
        item.trip = trip.trip
        return item
    }

    @Test func staysAreListedWithoutAskingAndOtherPlansOnlyWhenMarked() throws {
        let day = try makeTrip()
        add("ホテル", day: 1, kind: .stay, opens: 900, to: day)
        let dinner = add("お店", day: 1, kind: .food, fixed: 1020, to: day)
        add("集合", day: 2, kind: .other, fixed: 600, to: day)
        add("東本願寺", day: 1, kind: .sight, to: day)
        var preparation = Preparation(trip: day.trip, now: date(1), calendar: calendar)
        #expect(preparation.pending.map(\.title) == ["ホテル"])

        dinner.bookingNeeded = true
        preparation = Preparation(trip: day.trip, now: date(1), calendar: calendar)
        #expect(preparation.pending.map(\.title) == ["ホテル", "お店"])
        #expect(preparation.total == 2)
    }

    @Test func notBookedComesFirstInTripOrderAndBookedGoesBelow() throws {
        let day = try makeTrip()
        let second = add("旅館", day: 2, kind: .stay, to: day)
        let first = add("ホテル", day: 1, kind: .stay, opens: 900, to: day)
        let dinner = add("お店", day: 1, kind: .food, fixed: 1020, to: day)
        dinner.bookingNeeded = true
        dinner.bookedAt = date(1)
        let preparation = Preparation(trip: day.trip, now: date(1), calendar: calendar)
        #expect(preparation.pending.map(\.id) == [first.id, second.id])
        #expect(preparation.booked.map(\.title) == ["お店"])
        let days = ItineraryDays(dates: day.trip.dates, text: DateText(calendar: calendar, holidays: .bundled))
        #expect(preparation.nextBooking(days: days)?.title == "宿を予約する")
    }

    @Test func thePhaseFollowsTheTripDates() throws {
        let day = try makeTrip()
        #expect(Preparation(trip: day.trip, now: date(1), calendar: calendar).phase == .before(daysLeft: 8))
        #expect(Preparation(trip: day.trip, now: date(8), calendar: calendar).phase == .eve)
        #expect(Preparation(trip: day.trip, now: date(10), calendar: calendar).phase == .day(2))
        #expect(Preparation(trip: day.trip, now: date(12), calendar: calendar).phase == .after)
        day.trip.dates = .days(3)
        #expect(Preparation(trip: day.trip, now: date(1), calendar: calendar).phase == .before(daysLeft: nil))
    }

    @Test func todaysChecksAreByTimeAndLuggageIsUnknownUntilTheStayOpens() throws {
        let day = try makeTrip()
        add("お店", day: 1, kind: .food, fixed: 1020, to: day).bookingNeeded = true
        add("ホテル", day: 1, kind: .stay, opens: 900, to: day)
        add("朝の集合", day: 1, kind: .other, fixed: 600, to: day)
        let checks = Preparation.checks(day.trip.items(on: 1), nowMinutes: 840)
        #expect(checks.map(\.kind) == [.opens, .fixed, .luggage])
        #expect(checks[1].isBooked == false)
        #expect(Preparation.checks(day.trip.items(on: 1), nowMinutes: 960).map(\.kind) == [.opens, .fixed])
    }

    @Test func aBookingToDoComesBeforeUndecidedPlansOnThePlanHome() {
        let booking = NextBooking(id: UUID(), context: "1日目 ・ 宿", title: "宿を予約する")
        let picked = NextActionPicker.pick(
            dates: .days(2), trainSteps: [], undecidedPlanCount: 3, booking: booking
        )
        #expect(picked == .book(booking))
    }

    @Test func theUndoSnapshotKeepsTheBookingMarks() throws {
        let day = try makeTrip()
        let dinner = add("お店", day: 1, kind: .food, to: day)
        dinner.bookingNeeded = true
        dinner.bookedAt = date(1)
        let restored = ItineraryItem.restored(from: dinner.snapshot())
        #expect(restored.bookingNeeded == true)
        #expect(restored.bookedAt == date(1))
    }
}
