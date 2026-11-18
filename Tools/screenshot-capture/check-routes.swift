import Foundation
import MapKit

func search(_ query: String) async throws -> MKMapItem {
    let req = MKLocalSearch.Request()
    req.naturalLanguageQuery = query
    req.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 34.986, longitude: 135.759), latitudinalMeters: 2000, longitudinalMeters: 2000)
    let results = try await MKLocalSearch(request: req).start()
    guard let item = results.mapItems.first else { throw NSError(domain: "no result", code: 1) }
    return item
}
Task { @MainActor in
    do {
        let queries = ["京都駅 中央口", "ホテルグランヴィア京都", "イノダコーヒ ポルタ支店", "OGAWA COFFEE 京都駅中央口店", "東本願寺"]
        var places: [MKMapItem] = []
        for query in queries {
            let place = try await search(query)
            places.append(place)
            print("PLACE \(query): \(place.name ?? "") \(place.placemark.coordinate.latitude),\(place.placemark.coordinate.longitude) \(place.placemark.title ?? "")")
        }
        var records: [[String: Any]] = []
        for (from, to) in [(0,1),(1,2),(2,1),(0,3),(3,1),(0,4),(4,1)] {
            let req = MKDirections.Request()
            req.source = places[from]; req.destination = places[to]; req.transportType = .walking
            let route = try await MKDirections(request: req).calculate().routes[0]
            let pts = route.polyline.points()
            let coordinates = (0..<route.polyline.pointCount).map { [pts[$0].coordinate.latitude, pts[$0].coordinate.longitude] }
            records.append(["from": queries[from], "to": queries[to], "seconds": route.expectedTravelTime, "meters": route.distance, "coordinates": coordinates])
            print("ROUTE \(queries[from]) → \(queries[to]): \(route.expectedTravelTime / 60)min \(route.distance)m")
        }
        let data = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/romy-routes.json"))
    } catch { print("ERROR \(error)") }
    exit(0)
}
RunLoop.main.run()
