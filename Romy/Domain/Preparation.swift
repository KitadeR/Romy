import Foundation

/// What the 準備 tab shows in its first half (Notion 02 §6-3 決定 2026-10-27, Figma 28): the plans that need booking,
/// in the order of the trip, and on a day of the trip the day's checks. 持ち物 and the weather come later.
struct Preparation {
    enum Phase: Equatable {
        /// Before the trip; the days left are known only for a trip with dates.
        case before(daysLeft: Int?)
        /// The day before the first day: 「明日の準備」.
        case eve
        /// A day of the trip: 「今日の確認」.
        case day(Int)
        case after
    }

    /// One line of 「今日の確認」: a check-in that opens at a time, a plan whose time does not move, or the luggage
    /// whose place nobody has checked.
    enum CheckKind: Equatable { case opens, fixed, luggage }

    struct Check: Equatable {
        let kind: CheckKind
        let minutes: Int?
        let title: String
        /// For a fixed plan that needs booking: whether it is booked.
        let isBooked: Bool?
    }

    let phase: Phase
    /// Every plan that needs booking, not yet booked first, each group in the order of the trip.
    let pending: [ItineraryItem]
    let booked: [ItineraryItem]
    let checks: [Check]

    var total: Int { pending.count + booked.count }

    init(trip: Trip, now: Date = .now, calendar: Calendar = .current) {
        let days = ItineraryDays.count(of: trip.dates)
        let listed = trip.items.filter(\.needsBooking).sorted { lhs, rhs in
            let left = ItineraryDays.placement(of: lhs.day, dayCount: days) ?? Int.max
            let right = ItineraryDays.placement(of: rhs.day, dayCount: days) ?? Int.max
            if left != right { return left < right }
            let leftTime = lhs.fixedStartMinutes ?? lhs.notBeforeMinutes ?? Int.max
            let rightTime = rhs.fixedStartMinutes ?? rhs.notBeforeMinutes ?? Int.max
            return leftTime != rightTime ? leftTime < rightTime : lhs.order < rhs.order
        }
        pending = listed.filter { $0.bookedAt == nil }
        booked = listed.filter { $0.bookedAt != nil }
        phase = Self.phase(of: trip.dates, now: now, calendar: calendar)
        if case .day(let day) = phase {
            let nowMinutes = Trip.minutes(of: now, on: now, calendar: calendar) ?? 0
            checks = Self.checks(
                trip.items(on: day), nowMinutes: nowMinutes, leaving: !trip.stayLines(on: day).leaving.isEmpty
            )
        } else {
            checks = []
        }
    }

    /// 「1日目 ・ 11/9（土） 17:00 ・ 食事」: the day as the itinerary writes it, then the time and the kind.
    static func context(of item: ItineraryItem, days: ItineraryDays) -> String {
        let day = ItineraryDays.placement(of: item.day, dayCount: days.days.count)
            .map { days.caption(for: .day($0), hasDestination: true) } ?? "未定"
        let time = item.fixedStartMinutes.map { " \(DaySchedule.clock($0))" } ?? ""
        return [day + time, item.kind.label].compactMap { $0 }.joined(separator: " ・ ")
    }

    /// The black card's words: 「宿を予約する」 (「宿を決める」 for a stay decided later), 「お店を予約する」, otherwise
    /// 「予約する」.
    static func bookTitle(of item: ItineraryItem) -> String {
        switch item.kind {
        case .stay: item.stayKind == .later ? "宿を決める" : "宿を予約する"
        case .food: "お店を予約する"
        default: "予約する"
        }
    }

    /// What the Plan Home shows for the same plan as 準備's black card.
    func nextBooking(days: ItineraryDays) -> NextBooking? {
        pending.first.map {
            NextBooking(
                id: $0.id, context: "\(Self.context(of: $0, days: days)) ・ \($0.title)", title: Self.bookTitle(of: $0)
            )
        }
    }

    /// Bookings still to make from `day` on (or in 未定): 「これから」 under the day's checks. Today's own stay is
    /// there too while it is not booked, since the checks only have times.
    func ahead(of day: Int) -> [ItineraryItem] {
        pending.filter { ($0.day ?? Int.max) >= day }
    }

    static func phase(of dates: TripDates, now: Date, calendar: Calendar) -> Phase {
        switch TripPhase(dates: dates, today: now, calendar: calendar) {
        case .memories: return .after
        case .action: return dates.dayNumber(on: now, calendar: calendar).map(Phase.day) ?? .eve
        case .plan:
            guard case .range(let start, _) = dates else { return .before(daysLeft: nil) }
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: start)
            ).day
            return .before(daysLeft: days)
        }
    }

    /// The day's check-ins and fixed times still ahead, by time. While a stay has not opened yet, or after leaving a
    /// stay with plans still to go, the luggage has no checked place, so it says 「？」 rather than guessing
    /// (Notion 02 §6-4, §6-5 決定 2026-10-28 チェックアウト後の荷物).
    static func checks(_ plans: [ItineraryItem], nowMinutes: Int, leaving: Bool = false) -> [Check] {
        var checks: [Check] = []
        for plan in plans where plan.doneAt == nil {
            if plan.kind == .stay, let opens = plan.notBeforeMinutes {
                checks.append(Check(kind: .opens, minutes: opens, title: plan.title, isBooked: nil))
            } else if let fixed = plan.fixedStartMinutes, fixed >= nowMinutes {
                checks.append(Check(
                    kind: .fixed, minutes: fixed, title: plan.title,
                    isBooked: plan.needsBooking ? plan.bookedAt != nil : nil
                ))
            }
        }
        checks.sort { ($0.minutes ?? 0) < ($1.minutes ?? 0) }
        let waitsForStay = plans.contains {
            $0.kind == .stay && $0.doneAt == nil && ($0.notBeforeMinutes ?? 0) > nowMinutes
        }
        if waitsForStay || (leaving && plans.contains { $0.doneAt == nil }) {
            checks.append(Check(kind: .luggage, minutes: nil, title: "荷物の預け先は未確認", isBooked: nil))
        }
        return checks
    }
}
