import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Romy

@MainActor
struct WishListTests {
    private func makeContext() throws -> (ModelContext, Trip) {
        let container = try ModelContainer(
            for: Trip.self, ItineraryItem.self, WishPlace.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let trip = Trip(name: "東京", isNameAuto: false, destinations: [], dates: .days(2))
        context.insert(trip)
        return (context, trip)
    }

    private func wish(
        _ title: String, area: String? = nil, latitude: Double = 35.68, longitude: Double = 139.76,
        placeID: String? = nil, savedAt: Date = .now
    ) -> WishPlace {
        WishPlace(
            title: title, kind: .sight, category: "名所", area: area,
            latitude: latitude, longitude: longitude, placeID: placeID, now: savedAt
        )
    }

    @Test func groupsFollowTheWardsInTheOrderTheyWereSavedAndPutUnknownLast() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let list = [
            wish("a", area: nil, savedAt: start),
            wish("b", area: "渋谷区", savedAt: start + 1),
            wish("c", area: "千代田区", savedAt: start + 2),
            wish("d", area: "渋谷区", savedAt: start + 3)
        ]
        let groups = WishList.groups(list)
        #expect(groups.map(\.title) == ["渋谷区", "千代田区", WishList.otherTitle])
        #expect(groups[0].wishes.map(\.title) == ["b", "d"])
    }

    @Test func nearestFirstSortsByDistance() {
        let origin = CLLocation(latitude: 35.681, longitude: 139.767)
        let near = wish("近い", latitude: 35.682, longitude: 139.768)
        let far = wish("遠い", latitude: 35.70, longitude: 139.80)
        let sorted = WishList.nearestFirst([far, near], from: origin)
        #expect(sorted.map(\.wish.title) == ["近い", "遠い"])
        #expect(sorted[0].meters < sorted[1].meters)
    }

    @Test func distancesAreWrittenShort() {
        #expect(WishList.distanceText(850) == "850m")
        #expect(WishList.distanceText(1234) == "1.2km")
        #expect(WishList.distanceText(12_400) == "12km")
    }

    @Test func aPlaceIsAddedWhenItIsTheSameApplePlaceOrTheSameNameNearby() {
        let saved = wish("東京駅", placeID: "id-1")
        let same = ItineraryItem(title: "別の呼び名", day: 1, order: 0, kind: .sight, placeID: "id-1")
        let other = ItineraryItem(title: "東京駅", day: 1, order: 1, kind: .sight, placeID: "id-2")
        #expect(saved.isSamePlace(as: same))
        #expect(!saved.isSamePlace(as: other))

        let byName = wish("すし")
        let near = ItineraryItem(
            title: "すし", day: nil, order: 0, kind: .food, latitude: 35.6801, longitude: 139.7601
        )
        let farAway = ItineraryItem(
            title: "すし", day: nil, order: 1, kind: .food, latitude: 35.7, longitude: 139.9
        )
        #expect(byName.isSamePlace(as: near))
        #expect(!byName.isSamePlace(as: farAway))
        #expect(!byName.isSamePlace(as: ItineraryItem(title: "すし", day: nil, order: 2, kind: .nameOnly)))
    }

    @Test func addingAWishToADayKeepsTheWishAndMarksItAdded() throws {
        let (context, trip) = try makeContext()
        let saved = wish("東京駅", placeID: "id-1")
        context.insert(saved)
        saved.trip = trip
        #expect(trip.plan(for: saved) == nil)

        let plan = trip.addPlan(from: saved, toDay: 2)
        context.insert(plan)
        plan.trip = trip
        #expect(trip.plan(for: saved)?.day == 2)
        #expect(plan.placeID == "id-1")
        #expect(trip.wishes.count == 1)
    }

    @Test func aRemovedWishComesBackWithTheSameValues() throws {
        let (context, trip) = try makeContext()
        let saved = wish("東京駅", area: "千代田区", placeID: "id-1")
        context.insert(saved)
        saved.trip = trip
        let snapshot = saved.snapshot()
        context.delete(saved)
        context.processPendingChanges()
        #expect(trip.wishes.isEmpty)

        let restored = WishPlace.restored(from: snapshot)
        context.insert(restored)
        restored.trip = trip
        context.processPendingChanges()
        #expect(trip.wishes.count == 1)
        #expect(trip.wishes.first?.id == snapshot.id)
        #expect(trip.wishes.first?.area == "千代田区")
    }
}
