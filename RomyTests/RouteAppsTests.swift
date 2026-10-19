import CoreLocation
import Foundation
import Testing
@testable import Romy

@MainActor
struct RouteAppsTests {
    private let tokyo = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)
    private let shinjuku = CLLocationCoordinate2D(latitude: 35.6896, longitude: 139.7006)

    @Test func googleLinkCarriesTheDestinationOriginAndMode() throws {
        let url = try #require(RouteLink.googleURL(
            from: RoutePoint(coordinate: tokyo), to: RoutePoint(coordinate: shinjuku), mode: .transit
        ))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host == "www.google.com")
        #expect(query.first { $0.name == "destination" }?.value == "35.6896,139.7006")
        #expect(query.first { $0.name == "origin" }?.value == "35.6812,139.7671")
        #expect(query.first { $0.name == "travelmode" }?.value == "transit")
    }

    @Test func googleLinkWithoutAnOriginStartsFromWhereThePersonIs() throws {
        let url = try #require(RouteLink.googleURL(from: nil, to: RoutePoint(coordinate: shinjuku), mode: nil))
        let names = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) ?? []
        #expect(!names.contains("origin"))
        #expect(!names.contains("travelmode"))
    }

    @Test func googleLinkNamesThePlacesWhenTheyHaveNames() throws {
        let url = try #require(RouteLink.googleURL(
            from: RoutePoint(coordinate: tokyo, text: "大阪駅 大阪市北区"),
            to: RoutePoint(coordinate: shinjuku, text: "御堂筋 大阪市"), mode: .walking
        ))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "origin" }?.value == "大阪駅 大阪市北区")
        #expect(query.first { $0.name == "destination" }?.value == "御堂筋 大阪市")
    }

    @Test func aPlaceIsSearchedByItsNameAndWard() {
        let withWard = ItineraryItem(title: "大阪駅", day: 1, order: 0, kind: .sight, area: "大阪市北区")
        let noWard = ItineraryItem(title: "御堂筋", day: 1, order: 1, kind: .sight)
        #expect(RouteLink.searchText(withWard) == "大阪駅 大阪市北区")
        #expect(RouteLink.searchText(noWard) == "御堂筋")
    }

    @Test func everyTravelModeHasAGoogleMode() {
        #expect(TravelMode.allCases.map(\.googleMode) == ["walking", "driving", "transit"])
    }

    @Test func thePickedAppIsKeptUntilItIsCleared() {
        let before = RoutePreference.current
        defer { RoutePreference.current = before }
        RoutePreference.current = .google
        #expect(RoutePreference.current == .google)
        RoutePreference.current = nil
        #expect(RoutePreference.current == nil)
    }
}
