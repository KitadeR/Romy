import Foundation

/// A moment in Action where a proposal makes sense: the plan that is 今, and the next plan with a place after it.
/// The time between them is what the proposal fills (Notion 02 §6-4).
struct ActionOpportunity: Identifiable {
    /// The plan that is 今.
    let id: UUID
    let currentTitle: String
    /// Where the plan that is 今 is; the start when the person's own location is not known.
    let currentPlace: ProposalPlace?
    let next: ProposalPlace
    let nextTitle: String
    let nextStartMinutes: Int
    let nowMinutes: Int
    /// True when the next plan's time is fixed (it will not be moved); a guessed time follows the plans before it.
    let nextIsFixed: Bool
    /// Words put in as chips when the proposal opens, from the emoji tiles (段階4); empty from the itinerary.
    var seedWords: [String] = []

    var availableMinutes: Int { nextStartMinutes - nowMinutes }

    /// The opportunity after `current`, when a plan with a place comes later in the day.
    static func make(
        after current: ItineraryItem, in plans: [ItineraryItem], schedule: DaySchedule, nowMinutes: Int
    ) -> ActionOpportunity? {
        guard let index = plans.firstIndex(where: { $0.id == current.id }) else { return nil }
        for later in plans.dropFirst(index + 1) {
            guard let place = ProposalPlace(item: later), let slot = schedule.slot(for: later.id) else { continue }
            return ActionOpportunity(
                id: current.id, currentTitle: current.title, currentPlace: ProposalPlace(item: current),
                next: place, nextTitle: later.title, nextStartMinutes: slot.startMinutes,
                nowMinutes: nowMinutes, nextIsFixed: slot.isFixed
            )
        }
        return nil
    }
}

extension ProposalPlace {
    /// A plan's place; nil for a plan with a name only.
    init?(item: ItineraryItem) {
        guard let latitude = item.latitude, let longitude = item.longitude else { return nil }
        self.init(name: item.title, category: item.category ?? "none", latitude: latitude, longitude: longitude)
    }
}

/// Turns what the person typed into chips and conditions, until the model that splits a wish is in
/// (the cheap model, Notion 02 §6-4). A few words are known; anything else is searched as it was written.
enum ActionIntake {
    enum Result: Equatable {
        case chip(ProposalChip)
        case condition(ProposalCondition)
    }

    private struct Known {
        let words: [String]
        let query: String
        let category: String
        let activity: ProposalChip.Activity
    }

    private static let known = [
        Known(words: ["パン"], query: "パン屋", category: "bakery", activity: .buy),
        Known(words: ["コンビニ"], query: "コンビニ", category: "convenience", activity: .buy),
        Known(words: ["カフェ", "コーヒー", "喫茶"], query: "カフェ", category: "cafe", activity: .rest),
        Known(words: ["ランチ", "ごはん", "ご飯", "食事", "レストラン"], query: "レストラン", category: "restaurant", activity: .eat),
        Known(words: ["公園"], query: "公園", category: "park", activity: .rest),
        Known(words: ["海", "ビーチ", "浜"], query: "海岸", category: "beach", activity: .see)
    ]

    private static let walkLessWords = ["歩きたくない", "歩かない", "歩くのは少なめ", "あまり歩"]

    static func parse(_ text: String) -> Result? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if walkLessWords.contains(where: text.contains) {
            return .condition(ProposalCondition(text: "歩くのは少なめ", kind: .walkLess))
        }
        if let match = known.first(where: { entry in entry.words.contains(where: text.contains) }) {
            return .chip(ProposalChip(
                text: text, activity: match.activity, query: match.query, category: match.category
            ))
        }
        return .chip(ProposalChip(text: text))
    }
}
