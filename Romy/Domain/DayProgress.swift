import Foundation

/// Where a day stands in Action: which plans are 済み, 今, スキップ (Notion 02 §6-5 「済みを付ける・外す」).
/// 今 is the plan after the last one marked 済み (the first plan when none is). A plan before that which is not
/// 済み is スキップ; it stays on the list and can be marked later. The states come from the order, so
/// un-marking the last 済み makes that plan 今 again, and un-marking an earlier one makes it スキップ.
struct DayProgress {
    enum State: Equatable {
        case done, skipped, now, upcoming
    }

    struct Input {
        let id: UUID
        let isDone: Bool
    }

    private let states: [UUID: State]

    /// `isToday` is false for the other days of the trip: their 済み marks stay and can be undone,
    /// but there is no 今 or スキップ (Notion 02 §6-5: 「今」 does not move on other days).
    init(plans: [Input], isToday: Bool) {
        var states: [UUID: State] = [:]
        guard isToday else {
            for plan in plans { states[plan.id] = plan.isDone ? .done : .upcoming }
            self.states = states
            return
        }
        let lastDone = plans.lastIndex { $0.isDone }
        let nowIndex = (lastDone ?? -1) + 1
        for (index, plan) in plans.enumerated() {
            if index < nowIndex {
                states[plan.id] = plan.isDone ? .done : .skipped
            } else {
                states[plan.id] = index == nowIndex ? .now : .upcoming
            }
        }
        self.states = states
    }

    func state(of id: UUID) -> State { states[id] ?? .upcoming }
}

/// The three stages of a trip as the itinerary sees them (Notion 02 §6): Plan until the day before the trip,
/// Action from the day before to the last day, Memories after. Only a trip with fixed dates leaves Plan.
enum TripPhase: Equatable {
    case plan, action, memories

    init(dates: TripDates, today: Date, calendar: Calendar = .current) {
        guard case .range(let start, let end) = dates else {
            self = .plan
            return
        }
        let today = calendar.startOfDay(for: today)
        let eve = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start)) ?? start
        if today < eve {
            self = .plan
        } else if today <= calendar.startOfDay(for: end) {
            self = .action
        } else {
            self = .memories
        }
    }
}

extension TripDates {
    /// The 1-based day of the trip that `today` falls on; nil before the first day, after the last, or without dates.
    func dayNumber(on today: Date, calendar: Calendar = .current) -> Int? {
        guard case .range(let start, let end) = self else { return nil }
        let first = calendar.startOfDay(for: start)
        let day = calendar.startOfDay(for: today)
        guard day >= first, day <= calendar.startOfDay(for: end) else { return nil }
        return (calendar.dateComponents([.day], from: first, to: day).day ?? 0) + 1
    }
}
