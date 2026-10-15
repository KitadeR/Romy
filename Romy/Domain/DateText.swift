import Foundation

/// Japanese date labels used in trip creation: 「10/17（土）」「11/23（月・祝）」.
struct DateText {
    let calendar: Calendar
    let holidays: HolidayCalendar

    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    func day(_ date: Date, withMonth: Bool = true) -> String {
        let parts = calendar.dateComponents([.month, .day, .weekday], from: date)
        var mark = Self.weekdays[(parts.weekday ?? 1) - 1]
        if holidays.isHoliday(date, calendar: calendar) { mark += "・祝" }
        let number = withMonth ? "\(parts.month ?? 0)/\(parts.day ?? 0)" : "\(parts.day ?? 0)"
        return "\(number)（\(mark)）"
    }

    /// Chip sub-label: the month is left out of the end when it is the same month.
    func shortRange(_ start: Date, _ end: Date) -> String {
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
        return "\(day(start))〜\(day(end, withMonth: !sameMonth))"
    }

    /// Plain range without weekdays, for the Plan Home caption: 「11/9〜11/11」 (Figma 46:147).
    func plainRange(_ start: Date, _ end: Date) -> String {
        func monthDay(_ date: Date) -> String {
            let parts = calendar.dateComponents([.month, .day], from: date)
            return "\(parts.month ?? 0)/\(parts.day ?? 0)"
        }
        return calendar.isDate(start, inSameDayAs: end) ? monthDay(start) : "\(monthDay(start))〜\(monthDay(end))"
    }

    /// Selected range under the chips and in the collapsed row.
    func range(_ start: Date, _ end: Date) -> String {
        calendar.isDate(start, inSameDayAs: end) ? day(start) : "\(day(start))〜\(day(end))"
    }

    func dayCount(_ start: Date, _ end: Date) -> Int {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)
        )
        return (days.day ?? 0) + 1
    }

    /// Summary for the collapsed 日付 row.
    func summary(_ dates: TripDates) -> String {
        switch dates {
        case .undecided: "あとで決める"
        case .days(let count): "\(count)日間"
        case .range(let start, let end): range(start, end)
        }
    }
}
