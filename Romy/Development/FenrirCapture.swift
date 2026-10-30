#if DEBUG
import MapKit
import SwiftData
import SwiftUI

/// Submission photographs use an in-memory container. Never seeds or opens the person's saved trips.
enum FenrirCapture {
    static var screen: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-fenrir-screen"), args.indices.contains(index + 1),
              let value = Int(args[index + 1]), (1 ... 8).contains(value) else { return nil }
        return value
    }

    static let now = ISO8601DateFormatter().date(from: "2026-10-30T14:00:00+09:00")!
    static let day = Calendar.current.startOfDay(for: now)
    static let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
    static let hotel = "ホテルグランヴィア京都"
    static let cafeA = "イノダコーヒ ポルタ支店"
    static let cafeB = "OGAWA COFFEE 京都駅中央口店"
    static let titleA = "先に荷物を手放して、身軽に休む"
    static let titleB = "まず近くで座って休む"
    static let station = CLLocationCoordinate2D(latitude: 34.9863137, longitude: 135.7589287)
    static let hotelPoint = CLLocationCoordinate2D(latitude: 34.9858997, longitude: 135.7596767)
    static let cafeAPoint = CLLocationCoordinate2D(latitude: 34.986949, longitude: 135.760505)
    static let cafeBPoint = CLLocationCoordinate2D(latitude: 34.9873157, longitude: 135.7588014)
    static let destination = Destination(
        id: "26100",
        name: "京都市",
        context: "京都府",
        kind: .municipality,
        latitude: 34.9863137,
        longitude: 135.7589287)
    @MainActor static let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: Trip.self,
                ItineraryItem.self,
                WishPlace.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        } catch { fatalError("Cannot create isolated capture container: \(error)") }
    }()

    static func trip(applyingA: Bool = false) -> Trip {
        let trip = Trip(
            name: "秋の京都旅",
            isNameAuto: false,
            destinations: [destination],
            dates: .range(start: day, end: end),
            now: now)
        trip.dayStartMinutes = 810
        if screen == 2, let url = Bundle.main.url(forResource: "fenrir-kyoto-cover", withExtension: "png") {
            trip.photo = try? Data(contentsOf: url)
        }
        let arrival = item("京都駅に到着・駅周辺を散策", order: 0, point: station, kind: .sight, duration: 45)
        let temple = item(
            "東本願寺を散策",
            order: 1,
            point: .init(latitude: 34.9909714, longitude: 135.7586682),
            kind: .sight,
            duration: 30)
        let stay = item(hotel, order: 2, point: hotelPoint, kind: .stay, duration: 30)
        stay.notBeforeMinutes = 900
        stay.nightsCount = 1
        stay.checkOutMinutes = 720
        stay.bookedAt = now
        let dinner = item("京都駅周辺で夕食", order: 3, point: station, kind: .food, duration: 60)
        dinner.fixedStartMinutes = 1020
        arrival.photo = photo("fenrir-kyoto-station")
        temple.photo = photo("fenrir-higashi-honganji")
        stay.photo = photo("fenrir-granvia")
        dinner.photo = photo("fenrir-dinner")
        trip.items = [arrival, temple, stay, dinner]
        for item in trip.items {
            item.trip = trip
        }
        if applyingA {
            applyA(to: trip)
        }
        return trip
    }

    /// Author the selected change, then use the app's existing mutation and real itinerary models.
    /// This skips live candidate search; it does not substitute an authored itinerary view.
    private static func applyA(to trip: Trip) {
        let plans = trip.items(on: 1)
        let change = SceneApply(
            day: 1, currentID: plans[0].id, currentDurationMinutes: 30,
            added: [
                .init(title: "\(hotel)に荷物を預ける", kind: .other,
                      latitude: hotelPoint.latitude, longitude: hotelPoint.longitude, durationMinutes: 10),
                .init(title: "\(cafeA)で休む", kind: .food,
                      latitude: cafeAPoint.latitude, longitude: cafeAPoint.longitude, durationMinutes: 38)
            ],
            skipped: [plans[1].snapshot()], basis: plans.map { $0.snapshot() }
        )
        let (added, _) = trip.apply(change)
        trip.items.append(contentsOf: added)
        for item in added { item.trip = trip }
        added.first?.photo = photo("fenrir-granvia")
        added.last?.photo = photo("fenrir-cafe-a")
    }

    private static func photo(_ name: String) -> Data? {
        Bundle.main.url(forResource: name, withExtension: "png").flatMap { try? Data(contentsOf: $0) }
    }

    private static func item(
        _ title: String,
        order: Int,
        point: CLLocationCoordinate2D,
        kind: PlanKind,
        duration: Int) -> ItineraryItem {
        let item = ItineraryItem(
            title: title,
            day: 1,
            order: order,
            kind: kind,
            area: "京都市下京区",
            latitude: point.latitude,
            longitude: point.longitude,
            now: now)
        item.durationMinutes = duration
        item.travelMode = .walking
        return item
    }

    @MainActor static func creation() -> TripCreationModel {
        let model = TripCreationModel(today: day)
        model.destinations = [destination]
        model.dateMode = .specific
        model.rangeStart = day
        model.rangeEnd = end
        model.name = "秋の京都旅"
        model.openStep = .name
        return model
    }

    /// Measured route minutes plus allowance for the station building / underground stairs.
    @MainActor static func travel(for trip: Trip) -> TravelTimes {
        let travel = TravelTimes()
        let plans = trip.items(on: 1)
        for (index, pair) in zip(plans, plans.dropFirst()).enumerated() {
            guard let move = TravelTimes.move(from: pair.0, to: pair.1) else { continue }
            let values = plans.count == 5
                ? [(5, 119), (7, 320), (7, 320), (5, 119)]
                : [(10, 652), (12, 754), (5, 119)]
            travel.store(.ready(TravelEstimate(minutes: values[index].0, meters: values[index].1)), for: move)
        }
        return travel
    }
}

#endif
