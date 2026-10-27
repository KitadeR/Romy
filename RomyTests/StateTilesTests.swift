import Foundation
import Testing
@testable import Romy

/// The emoji tiles and the strength slider (Figma 26-02・03・04).
struct StateTilesTests {
    @Test func eachStepUpIsFeltMoreStrongly() {
        let steps = TiredStrength.allCases.map(\.impact)
        for (lower, higher) in zip(steps, steps.dropFirst()) {
            #expect(higher.weight >= lower.weight)
            #expect(higher.intensity > lower.intensity)
        }
        #expect(steps.allSatisfy { (0...2).contains($0.weight) && (0...1).contains($0.intensity) })
    }

}
