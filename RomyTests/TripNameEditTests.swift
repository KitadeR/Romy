import Foundation
import Testing
@testable import Romy

@MainActor
struct TripNameEditTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let kyoto = Destination(id: "261009", name: "京都市", context: "京都府", kind: .municipality)

    @Test func aNameTheyTypeIsTheirOwnAndTrimmed() {
        let edited = TripNaming.edited(
            "  秋の京都  ", destinations: [kyoto], dates: .undecided, existingNames: [], calendar: calendar
        )
        #expect(edited.name == "秋の京都")
        #expect(edited.isAuto == false)
    }

    @Test func aBlankNameGoesBackToTheAutomaticOne() {
        let edited = TripNaming.edited(
            "   ", destinations: [kyoto], dates: .undecided, existingNames: [], calendar: calendar
        )
        #expect(edited.name == "京都旅行")
        #expect(edited.isAuto == true)
    }

    @Test func theAutomaticNameAvoidsTheOtherTripsNames() {
        let edited = TripNaming.edited(
            "", destinations: [kyoto], dates: .undecided, existingNames: ["京都旅行"], calendar: calendar
        )
        #expect(edited.name == "京都旅行 2")
    }

    @Test func aTooLongNameIsCut() {
        let long = String(repeating: "あ", count: TripNaming.longestName + 10)
        let edited = TripNaming.edited(long, destinations: [], dates: .undecided, existingNames: [], calendar: calendar)
        #expect(edited.name.count == TripNaming.longestName)
    }

    @Test func aNameAnotherTripHasIsAllowed() {
        let edited = TripNaming.edited(
            "京都旅行", destinations: [kyoto], dates: .undecided, existingNames: ["京都旅行"], calendar: calendar
        )
        #expect(edited.name == "京都旅行")
        #expect(edited.isAuto == false)
    }
}
