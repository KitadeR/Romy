import Foundation
import Testing
@testable import Romy

@MainActor
struct DurationTextTests {
    @Test func lengthsAreWrittenShort() {
        #expect(DurationText.text(minutes: 15) == "15分")
        #expect(DurationText.text(minutes: 60) == "1時間")
        #expect(DurationText.text(minutes: 65) == "1時間5分")
        #expect(DurationText.text(minutes: 180) == "3時間")
    }

    @Test func aTravelEstimateUsesTheSameWords() {
        #expect(TravelEstimate(minutes: 119, meters: 7300).durationText == "1時間59分")
    }
}
