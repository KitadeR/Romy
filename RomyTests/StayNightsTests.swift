import Foundation
@testable import Romy
import SwiftData
import Testing

@MainActor
struct StayNightsTests {
    private struct Day {
        let context: ModelContext
        let trip: Trip
    }

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    /// A trip of 11/9〜11/12 (4 days).
    private func makeTrip() throws -> Day {
        let container = try ModelContainer(
            for: Trip.self, ItineraryItem.self, WishPlace.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let trip = Trip(name: "京都旅行", isNameAuto: true, destinations: [], dates: .range(start: date(9), end: date(12)))
        context.insert(trip)
        return Day(context: context, trip: trip)
    }

    @discardableResult
    private func add(
        _ title: String, day: Int?, kind: PlanKind = .stay, nights: Int? = nil, to trip: Day
    ) -> ItineraryItem {
        let item = ItineraryItem(title: title, day: day, order: trip.trip.nextOrder(on: day), kind: kind)
        item.nightsCount = nights
        trip.context.insert(item)
        item.trip = trip.trip
        return item
    }

    @Test func aStayOfTwoNightsShowsTheSecondNightAndLeavingTheDayAfter() throws {
        let day = try makeTrip()
        let hotel = add("ホテル", day: 1, nights: 2, to: day)
        hotel.checkOutMinutes = 660
        #expect(day.trip.stayLines(on: 1).leaving.isEmpty)
        #expect(day.trip.stayLines(on: 1).nights.isEmpty)
        #expect(day.trip.stayLines(on: 2).nights == [StayLine(kind: .night(2), stay: hotel)])
        #expect(day.trip.stayLines(on: 2).nights.first?.note == "2泊目")
        #expect(day.trip.stayLines(on: 3).leaving == [StayLine(kind: .leaving, stay: hotel)])
        #expect(day.trip.stayLines(on: 3).leaving.first?.note == "11:00までにチェックアウト")
        #expect(day.trip.stayLines(on: 3).nights.isEmpty)
    }

    @Test func onAMovingDayTheFirstStayIsLeftAndTonightIsTheNextOne() throws {
        let day = try makeTrip()
        let hotel = add("ホテル", day: 1, nights: 2, to: day)
        let inn = add("旅館", day: 3, to: day)
        #expect(day.trip.stayTonight(on: 1)?.id == hotel.id)
        #expect(day.trip.stayTonight(on: 2)?.id == hotel.id)
        #expect(day.trip.stayLines(on: 3).leaving.map(\.stay.id) == [hotel.id])
        #expect(day.trip.stayTonight(on: 3)?.id == inn.id)
        #expect(day.trip.stayTonight(on: 4) == nil)
    }

    @Test func nightsGoUpToTheEndOfTheTripAndKeepTheirNumberWhenItIsShorter() throws {
        let day = try makeTrip()
        #expect(StayNights.maxNights(from: 1, dayCount: 4) == 3)
        #expect(StayNights.maxNights(from: 4, dayCount: 4) == 1)
        #expect(StayNights.maxNights(from: nil, dayCount: 4) == nil)
        #expect(StayNights.maxNights(from: 1, dayCount: 0) == nil)
        let hotel = add("ホテル", day: 2, nights: 3, to: day)
        day.trip.dates = .range(start: date(9), end: date(11))
        #expect(hotel.nights == 3)
        #expect(day.trip.stayLines(on: 3).nights.map(\.kind) == [.night(2)])
    }

    @Test func aFriendsHouseNeedsNoBookingAndAStayDecidedLaterIsToDecide() throws {
        let day = try makeTrip()
        let friend = add("さきの家", day: 1, to: day)
        friend.stayKind = .friend
        let later = add("宿", day: 2, to: day)
        later.stayKind = .later
        add("ホテル", day: 3, to: day)
        let preparation = Preparation(trip: day.trip, now: date(1), calendar: calendar)
        #expect(preparation.pending.map(\.title) == ["宿", "ホテル"])
        #expect(Preparation.bookTitle(of: later) == "宿を決める")
    }

    @Test func luggageIsUncheckedAfterLeavingAStayWithPlansStillToGo() throws {
        let day = try makeTrip()
        add("ホテル", day: 1, to: day)
        add("清水寺", day: 2, kind: .sight, to: day)
        #expect(Preparation(trip: day.trip, now: date(10, 9), calendar: calendar).checks.map(\.kind) == [.luggage])
        #expect(Preparation.checks([], nowMinutes: 540, leaving: true).isEmpty)
    }

    @Test func arrivingAfterTheLastCheckInIsTooLate() throws {
        let day = try makeTrip()
        let hotel = add("ホテル", day: 1, to: day)
        #expect(!hotel.arrivesTooLate(at: 23 * 60))
        hotel.lastCheckInMinutes = 22 * 60
        #expect(!hotel.arrivesTooLate(at: 22 * 60))
        #expect(hotel.arrivesTooLate(at: 22 * 60 + 10))
    }

    @Test func theUndoSnapshotKeepsTheStayRules() throws {
        let day = try makeTrip()
        let hotel = add("ホテル", day: 1, nights: 2, to: day)
        hotel.checkOutMinutes = 660
        hotel.lastCheckInMinutes = 1320
        hotel.stayKind = .rental
        let restored = ItineraryItem.restored(from: hotel.snapshot())
        #expect(restored.nights == 2)
        #expect(restored.checkOutMinutes == 660)
        #expect(restored.lastCheckInMinutes == 1320)
        #expect(restored.stayKind == .rental)
    }
}
