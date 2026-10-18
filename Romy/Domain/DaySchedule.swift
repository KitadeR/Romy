import Foundation

/// The times shown in the left column of a day (Notion 02 §6-5 ③一日の始まり, 時刻の見せ方).
/// A guessed start (目安) is the end of the plan before it, or the day's start for the first plan.
/// A fixed start (鍵) stays where the person put it, and the plans after it follow.
/// A plan marked 済み moves the guess of the plans after it to the time it was marked, so they are counted
/// again from now (Notion 02 §6-5 「目安の時刻は済みになるたびに今の時刻から計算し直す」).
/// Travel time between plans is not counted yet; it comes with the travel rows (Notion 05).
struct DaySchedule {
    struct Slot: Equatable {
        let id: UUID
        let startMinutes: Int
        let endMinutes: Int
        let isFixed: Bool

        /// How far through the plan `nowMinutes` is, from 0 (not started) to 1 (over): where the dot of 今 sits.
        /// It stops at the bottom edge once the time is over, since the next plan starts only when this one is
        /// marked 済み (Notion 02 §6-5).
        func progress(at nowMinutes: Int) -> Double {
            guard endMinutes > startMinutes else { return 0 }
            return min(max(Double(nowMinutes - startMinutes) / Double(endMinutes - startMinutes), 0), 1)
        }
    }

    struct Input {
        let id: UUID
        let durationMinutes: Int
        let fixedStartMinutes: Int?
        /// When the plan was marked 済み that day, in minutes after midnight; the plans after it count from here.
        var finishedAtMinutes: Int?
    }

    let slots: [Slot]

    init(dayStartMinutes: Int, plans: [Input]) {
        var cursor = dayStartMinutes
        slots = plans.map { plan in
            let start = plan.fixedStartMinutes ?? cursor
            let end = start + max(plan.durationMinutes, 5)
            cursor = plan.finishedAtMinutes ?? end
            return Slot(id: plan.id, startMinutes: start, endMinutes: end, isFixed: plan.fixedStartMinutes != nil)
        }
    }

    func slot(for id: UUID) -> Slot? { slots.first { $0.id == id } }

    /// 「9:00」「25:30」 (past midnight keeps counting, so a late plan is not mistaken for a morning one).
    static func clock(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// 「2h 00m」 style used in the sheet's big number.
    static func lengthParts(_ minutes: Int) -> (hours: Int, minutes: Int) { (minutes / 60, minutes % 60) }
}

extension Trip {
    /// The times of one day's plans, counted from the trip's 1日の始まり. With the day's date, the time a plan
    /// was marked 済み that day counts as when it ended; a mark made on another date is not used.
    func schedule(of plans: [ItineraryItem], on dayDate: Date? = nil, calendar: Calendar = .current) -> DaySchedule {
        DaySchedule(
            dayStartMinutes: dayStartMinutes,
            plans: plans.map {
                DaySchedule.Input(
                    id: $0.id, durationMinutes: $0.durationMinutes, fixedStartMinutes: $0.fixedStartMinutes,
                    finishedAtMinutes: Self.minutes(of: $0.doneAt, on: dayDate, calendar: calendar)
                )
            }
        )
    }

    /// The clock time of `date` in minutes after midnight, when it falls on `day`.
    static func minutes(of date: Date?, on day: Date?, calendar: Calendar) -> Int? {
        guard let date, let day, calendar.isDate(date, inSameDayAs: day) else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
