import Foundation

/// A tab of the itinerary (Notion 02 §6-3, §6-5): 「全体／未定／11/9 1日目…」.
enum ItineraryTab: Hashable {
    case all, undecided
    case day(Int)

    /// The day a plan added from this tab goes to (Notion 02 §6-6 ＋ボタン): a day tab gives that day,
    /// anything else 未定.
    var dayForNewPlan: Int? {
        if case .day(let number) = self { number } else { nil }
    }
}

/// The days of a trip and the words around them, for the itinerary.
struct ItineraryDays {
    struct Day: Hashable {
        let number: Int
        /// Nil for a day-count trip.
        let date: Date?
    }

    let dates: TripDates
    let text: DateText

    var days: [Day] {
        switch dates {
        case .undecided:
            return []
        case .days(let count):
            return (1...max(count, 1)).map { Day(number: $0, date: nil) }
        case .range(let start, let end):
            let first = text.calendar.startOfDay(for: start)
            return (1...max(text.dayCount(start, end), 1)).map {
                Day(number: $0, date: text.calendar.date(byAdding: .day, value: $0 - 1, to: first))
            }
        }
    }

    static func count(of dates: TripDates, calendar: Calendar = .current) -> Int {
        switch dates {
        case .undecided: 0
        case .days(let count): count
        case .range(let start, let end):
            (calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)
            ).day ?? 0) + 1
        }
    }

    /// Where a plan is shown: its day, or 未定 (nil) when it has none or the day is past the end of the trip.
    static func placement(of day: Int?, dayCount: Int) -> Int? {
        guard let day, day >= 1, day <= dayCount else { return nil }
        return day
    }

    /// Tab label: 「11/9 1日目」 with dates, 「1日目」 with a day count.
    func tabLabel(_ day: Day) -> String {
        guard let date = day.date else { return "\(day.number)日目" }
        let parts = text.calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0) \(day.number)日目"
    }

    /// Name of the day in messages: 「1日目」.
    static func name(of day: Int?) -> String {
        day.map { "\($0)日目" } ?? "未定"
    }

    /// The line under the trip name (Figma page 6 「16.」).
    func caption(for tab: ItineraryTab, hasDestination: Bool) -> String {
        switch dates {
        case .undecided:
            return hasDestination ? "いつ行くか 未定" : "行き先 未定 ・ いつ行くか 未定"
        case .days(let count):
            switch tab {
            case .all: return "\(count)日間 ・ 日付未定"
            case .undecided: return "日がまだ決まっていない予定"
            case .day(let number): return "\(number)日目"
            }
        case .range(let start, let end):
            switch tab {
            case .all: return "\(text.range(start, end)) ・ \(text.dayCount(start, end))日間"
            case .undecided: return "日がまだ決まっていない予定"
            case .day(let number):
                guard let date = days.first(where: { $0.number == number })?.date else { return "\(number)日目" }
                return "\(number)日目 ・ \(text.day(date))"
            }
        }
    }

    /// The note after marking 済み: 「清水寺を済みにしました」 / 「清水寺の済みを取り消しました」 (Notion 02 §6-5).
    static func doneMessage(title: String, isDone: Bool) -> String {
        isDone ? "\(title)を済みにしました" : "\(title)の済みを取り消しました"
    }

    /// The note after adding (Figma 15-9): 「伏見稲荷大社を1日目に追加しました」.
    static func addedMessage(title: String, day: Int?) -> String {
        "\(title)を\(name(of: day))に追加しました"
    }
}
