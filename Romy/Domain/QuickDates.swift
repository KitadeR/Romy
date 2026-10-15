import Foundation

/// The quick date chips in trip creation (Notion 02 §6-3, agreed 2026-10-13).
struct QuickDates {
    enum Kind: Hashable { case thisWeekend, nextWeekend, nextLongWeekend }

    struct Option: Identifiable, Hashable {
        let kind: Kind
        let start: Date
        let end: Date
        var id: Kind { kind }

        var title: String {
            switch kind {
            case .thisWeekend: "今週末"
            case .nextWeekend: "来週末"
            case .nextLongWeekend: "次の3連休"
            }
        }
    }

    let calendar: Calendar
    let holidays: HolidayCalendar

    func options(today: Date) -> [Option] {
        var result: [Option] = []
        let weekend = thisWeekend(today: today)
        result.append(Option(kind: .thisWeekend, start: weekend.start, end: weekend.end))
        result.append(Option(kind: .nextWeekend, start: add(7, to: weekend.start), end: add(7, to: weekend.end)))
        if let long = nextLongWeekend(today: today) {
            result.append(Option(kind: .nextLongWeekend, start: long.start, end: long.end))
        }
        return result
    }

    /// Saturday–Sunday of this week. On Sunday the weekend is ending, so the next one is used.
    func thisWeekend(today: Date) -> (start: Date, end: Date) {
        let day = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: day) // 1 = Sunday, 7 = Saturday
        let daysToSaturday = weekday == 1 ? 6 : 7 - weekday
        let saturday = add(daysToSaturday, to: day)
        return (saturday, add(1, to: saturday))
    }

    /// The first run of 3 or more days off (Saturday, Sunday or holiday) starting today or later.
    /// A run already going on before today is skipped. Nil when the holiday list does not cover it.
    func nextLongWeekend(today: Date) -> (start: Date, end: Date)? {
        let first = calendar.startOfDay(for: today)
        var day = first
        // A run that started before today is not "next".
        while isDayOff(add(-1, to: day)), isDayOff(day) {
            day = add(1, to: day)
        }
        var runStart: Date?
        var runLength = 0
        while holidays.isCovered(day, calendar: calendar) {
            if isDayOff(day) {
                if runStart == nil { runStart = day }
                runLength += 1
            } else {
                if let runStart, runLength >= 3 { return (runStart, add(-1, to: day)) }
                runStart = nil
                runLength = 0
            }
            day = add(1, to: day)
        }
        return nil
    }

    private func isDayOff(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7 || holidays.isHoliday(date, calendar: calendar)
    }

    private func add(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }
}
