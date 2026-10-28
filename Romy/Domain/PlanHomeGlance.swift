import Foundation
import SwiftData

/// What the Plan Home shows besides the next action (Notion 02 §6-3 採用 2026-10-28, Figma 29): the one-line summary
/// of 準備, a glance at the itinerary day by day, and on the day before the trip, tomorrow's first plan and the
/// plans after it.
enum PlanHomeGlance {
    struct DayCount: Identifiable, Equatable {
        let day: Int
        /// 「11/9」 with dates, 「1日目」 with a day count.
        let label: String
        let count: Int
        var id: Int { day }
    }

    /// One plan of tomorrow with its time: 「13:00 清水寺」, 「15:00から ホテル ・ 予約：済み」.
    struct Line: Equatable {
        let id: UUID
        let text: String
    }

    struct Eve: Equatable {
        /// 「京都」: where the trip goes (its short name), or the trip's name without a destination.
        let place: String
        /// Tomorrow's first plan, 「10:30 伏見稲荷大社」; nil when tomorrow has no plans.
        let first: Line?
        let rest: [Line]
    }

    /// 「準備 ・ 予約 3つ中1つ済み」; nil for a trip with nothing to book.
    static func summary(_ preparation: Preparation) -> String? {
        guard preparation.total > 0 else { return nil }
        return "準備 ・ 予約 \(preparation.total)つ中\(preparation.booked.count)つ済み"
    }

    /// How many plans each day has. A trip without dates or a day count has no days to show.
    static func dayCounts(of trip: Trip, days: ItineraryDays) -> [DayCount] {
        days.days.map { day in
            let label = day.date.map { date in
                let parts = days.text.calendar.dateComponents([.month, .day], from: date)
                return "\(parts.month ?? 0)/\(parts.day ?? 0)"
            } ?? "\(day.number)日目"
            return DayCount(day: day.number, label: label, count: trip.items(on: day.number).count)
        }
    }

    /// Tomorrow is the first day. Times are the itinerary's guesses without travel, which is enough for the order.
    /// A trip being deleted (the list deletes the open trip just after moving off it) is read as empty.
    static func eve(of trip: Trip) -> Eve {
        guard !trip.isDeleted, trip.modelContext != nil else { return Eve(place: "", first: nil, rest: []) }
        let plans = trip.items(on: 1)
        let schedule = trip.schedule(of: plans)
        let lines = plans.compactMap { plan in
            schedule.slot(for: plan.id).map { Line(id: plan.id, text: line(plan, startMinutes: $0.startMinutes)) }
        }
        let place = trip.destinations.first?.shortName ?? trip.name
        return Eve(place: place, first: lines.first, rest: Array(lines.dropFirst()))
    }

    /// The white button: 「2日目の宿を予約する」, 「1日目のお店を予約する」; any other plan by its name, 「Gionを予約する」.
    static func bookTitle(of item: ItineraryItem) -> String {
        guard item.kind == .stay || item.kind == .food else { return "\(item.title)を予約する" }
        return (item.day.map { "\($0)日目の" } ?? "") + Preparation.bookTitle(of: item)
    }

    private static func line(_ plan: ItineraryItem, startMinutes: Int) -> String {
        guard plan.kind == .stay, let opens = plan.notBeforeMinutes else {
            return "\(DaySchedule.clock(startMinutes)) \(plan.title)"
        }
        let booking = plan.needsBooking ? (plan.bookedAt == nil ? " ・ 予約：まだ" : " ・ 予約：済み") : ""
        return "\(DaySchedule.clock(opens))から \(plan.title)\(booking)"
    }
}
