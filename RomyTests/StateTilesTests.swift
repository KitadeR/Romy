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

    @Test func theTilesBecomeWordsTheProposalUnderstands() {
        #expect(ActionState.bridgeWords([.tired], strength: .little) == ["カフェで休む"])
        #expect(ActionState.bridgeWords([.tired], strength: .quite) == ["カフェで休む", "あまり歩きたくない"])
        #expect(ActionState.bridgeWords([.wantSit, .hungry], strength: nil) == ["カフェで休む", "ごはんを食べる"])
        #expect(ActionState.bridgeWords([.heavyLuggage], strength: nil).isEmpty)
    }

    @Test func theBridgeChipIsNamedShortInMessages() {
        #expect(ActionProposalModel.stem("カフェで休む") == "カフェ")
        #expect(ActionProposalModel.stem("ごはんを食べる") == "ごはん")
    }

    @Test func theBridgeWordsAreReadAsChipsAndConditions() {
        let words = ActionState.bridgeWords([.tired, .hungry], strength: .very)
        let parsed = words.compactMap(ActionIntake.parse)
        #expect(parsed.count == 3)
        let walkLess = parsed.contains { result in
            if case .condition(let condition) = result { condition.kind == .walkLess } else { false }
        }
        #expect(walkLess)
    }
}
