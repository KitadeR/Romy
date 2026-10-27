import Foundation

/// How the person is, picked from the emoji tiles (Figma 26-02, adopted 2026-10-25). The first build has four;
/// 「雨をよけたい」「時間が余った」 come when there is something behind them (2026-10-27).
enum ActionState: String, CaseIterable, Hashable {
    case tired, heavyLuggage, hungry, wantSit

    var emoji: String {
        switch self {
        case .tired: "😮‍💨"
        case .heavyLuggage: "🧳"
        case .hungry: "🍙"
        case .wantSit: "☕"
        }
    }

    var label: String {
        switch self {
        case .tired: "疲れた"
        case .heavyLuggage: "荷物が重い"
        case .hungry: "お腹がすいた"
        case .wantSit: "座って休みたい"
        }
    }

    /// Only being tired is asked how strongly (Figma 26-03); luggage is not.
    var hasStrength: Bool { self == .tired }
}

/// How tired, from the slider (Figma 26-03・04). The steps and their numbers are provisional, to be tried and
/// changed (Notion 02 §6-4, 2026-10-25).
enum TiredStrength: Int, CaseIterable, Comparable {
    case little, quite, very, cannotWalk

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var emoji: String {
        switch self {
        case .little: "🙂"
        case .quite: "😮‍💨"
        case .very: "🥵"
        case .cannotWalk: "🫠"
        }
    }

    var label: String {
        switch self {
        case .little: "少し"
        case .quite: "けっこう"
        case .very: "かなり"
        case .cannotWalk: "もう歩けない"
        }
    }

    /// One way, from where the person is; nil keeps the usual limit (`WalkLimit`).
    var oneWayCapMinutes: Int? {
        switch self {
        case .little: nil
        case .quite: 7
        case .very: 4
        case .cannotWalk: 3
        }
    }

    /// Places added to the day, not counting the plans already in it (the stay, the next plan).
    var maxAddedPlaces: Int {
        switch self {
        case .little, .quite: 2
        case .very, .cannotWalk: 1
        }
    }

    /// 「今いる近くで座って休む案だけ」: the rest is looked for near where the person is, never near the stay.
    var restsNearHereOnly: Bool { self == .cannotWalk }

    /// 「この段だと」 under the slider (Figma 26-03・04).
    var whatChanges: [String] {
        switch self {
        case .little: ["・いつもの範囲で探す"]
        case .quite: ["・歩くのは片道7分まで", "・座れる所を優先"]
        case .very: ["・歩くのは片道4分まで", "・座れる所だけ", "・立ち寄りは1か所"]
        case .cannotWalk: ["・歩くのは次の予定へ向かう道だけ", "・今いる近くで座って休む案だけ"]
        }
    }
}

extension TiredStrength {
    /// The words under the big emoji (Figma 26-03): 「けっこう疲れた」.
    var phrase: String {
        switch self {
        case .little: "少し疲れた"
        case .quite: "けっこう疲れた"
        case .very: "かなり疲れた"
        case .cannotWalk: "もう歩けない"
        }
    }

    /// Each step up is felt once, stronger the higher it goes (Figma 26-03・04): the weight (light, medium, heavy) and
    /// intensity (0 to 1) of `SensoryFeedback.impact(weight:intensity:)`
    /// (SwiftUI, iOS 17; checked in the SDK 2026-10-27).
    var impact: (weight: Int, intensity: Double) {
        switch self {
        case .little: (0, 0.5)
        case .quite: (1, 0.7)
        case .very: (2, 0.85)
        case .cannotWalk: (2, 1.0)
        }
    }
}

extension ActionState {
    /// Until the comparison of 25の3版 is built (段階5), the states open the proposal that already exists, as the
    /// words it understands (`ActionIntake`). 「荷物が重い」 has no word there yet; it is used from 段階5.
    static func bridgeWords(_ states: Set<ActionState>, strength: TiredStrength?) -> [String] {
        var words: [String] = []
        if states.contains(.tired) || states.contains(.wantSit) { words.append("カフェで休む") }
        if states.contains(.hungry) { words.append("ごはんを食べる") }
        if states.contains(.tired), let strength, strength >= .quite { words.append("あまり歩きたくない") }
        return words
    }
}
