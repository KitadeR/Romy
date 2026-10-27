import Foundation

/// The one thing the Plan Home shows (Notion 02 §6-2, agreed 2026-10-07):
/// a Shinkansen step if one can move forward → a plan to book (§6-3, 2026-10-27) → plans in 未定 to put on a day
/// → add plans.
/// Plan has no "nothing to do"; the last choice is always adding plans.
enum NextAction: Equatable {
    /// The next step of a Shinkansen move, e.g. 「乗り方を選ぶ」 (step 1 of 6).
    case trainStep(TrainStep)
    /// The next step needs the official booking, which needs the trip's dates.
    case decideDates(for: TrainStep)
    /// The first plan in 準備 that is not booked yet: the same one as 準備's black card (Notion 02 §6-3, 2026-10-27).
    case book(NextBooking)
    /// Plans without a day, in a trip that has days.
    case placeUndecided(count: Int)
    case addPlans
}

/// A Shinkansen move that still has a step to take. Filled from the itinerary once it exists.
struct TrainStep: Equatable {
    /// 「新幹線 東京→京都」
    let route: String
    /// 「乗り方を選ぶ」
    let title: String
    let number: Int
    let total: Int
    /// 1-based day for day-count or dated trips; nil while the move sits in 未定.
    let day: Int?
    let departure: Date?
    /// Order the move was added, used for moves in 未定.
    let addedOrder: Int
    /// True when this step is booking at the official service, which needs fixed dates.
    let needsTripDates: Bool
}

/// A plan to book, as the Plan Home shows it: 「1日目 ・ 宿 ホテル（例）京都駅前」 and 「宿を予約する」.
struct NextBooking: Equatable {
    let id: UUID
    let context: String
    let title: String
}

enum NextActionPicker {
    static func pick(
        dates: TripDates, trainSteps: [TrainStep], undecidedPlanCount: Int, booking: NextBooking? = nil
    ) -> NextAction {
        if let step = trainSteps.sorted(by: comesFirst).first {
            if step.needsTripDates, case .range = dates { return .trainStep(step) }
            return step.needsTripDates ? .decideDates(for: step) : .trainStep(step)
        }
        if let booking { return .book(booking) }
        if undecidedPlanCount > 0, dates != .undecided {
            return .placeUndecided(count: undecidedPlanCount)
        }
        return .addPlans
    }

    /// Nearer day first; on the same day the earlier departure; moves in 未定 last, in the order added.
    nonisolated private static func comesFirst(_ lhs: TrainStep, _ rhs: TrainStep) -> Bool {
        switch (lhs.day, rhs.day) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.addedOrder < rhs.addedOrder
        default:
            return (lhs.departure ?? .distantFuture) < (rhs.departure ?? .distantFuture)
        }
    }
}
