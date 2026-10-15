import Foundation
import Observation

/// State of the trip creation sheet. One card is open at a time (Notion 02 §2).
@Observable
final class TripCreationModel {
    enum Step: Int, CaseIterable { case destinations, dates, name }

    enum DateMode: Hashable { case later, days, specific }

    var openStep: Step = .destinations
    var destinations: [Destination] = []
    var dateMode: DateMode = .later
    var dayCount = 3
    var rangeStart: Date?
    var rangeEnd: Date?
    var selectedQuickDate: QuickDates.Kind?
    var isCalendarOpen = false
    var name = ""

    let calendar: Calendar
    let holidays: HolidayCalendar
    let today: Date

    init(calendar: Calendar = .current, holidays: HolidayCalendar = .bundled, today: Date = .now) {
        self.calendar = calendar
        self.holidays = holidays
        self.today = calendar.startOfDay(for: today)
    }

    var quickDates: QuickDates { QuickDates(calendar: calendar, holidays: holidays) }
    var dateText: DateText { DateText(calendar: calendar, holidays: holidays) }

    var dates: TripDates {
        switch dateMode {
        case .later: return .undecided
        case .days: return .days(dayCount)
        case .specific:
            guard let rangeStart else { return .undecided }
            return .range(start: rangeStart, end: rangeEnd ?? rangeStart)
        }
    }

    /// 「日付を指定」 needs a day before going on.
    var canContinue: Bool {
        openStep != .dates || dateMode != .specific || rangeStart != nil
    }

    func autoName(existingNames: [String]) -> String {
        TripNaming.autoName(destinations: destinations, dates: dates, existingNames: existingNames, calendar: calendar)
    }

    func toggle(_ destination: Destination) {
        if let index = destinations.firstIndex(where: { $0.id == destination.id }) {
            destinations.remove(at: index)
        } else {
            destinations.append(destination)
        }
    }

    func choose(_ option: QuickDates.Option) {
        selectedQuickDate = option.kind
        isCalendarOpen = false
        rangeStart = option.start
        rangeEnd = option.end
    }

    func openCalendar() {
        selectedQuickDate = nil
        isCalendarOpen = true
    }

    /// First tap sets the start; the next tap on the same day or later sets the end.
    func tapCalendarDay(_ day: Date) {
        if let start = rangeStart, rangeEnd == nil, day >= start {
            rangeEnd = day
        } else {
            rangeStart = day
            rangeEnd = nil
        }
    }

    /// Moves to the next card. Returns true when the last card was confirmed.
    func advance() -> Bool {
        guard let next = Step(rawValue: openStep.rawValue + 1) else { return true }
        if openStep == .dates, dateMode == .specific, rangeEnd == nil { rangeEnd = rangeStart }
        openStep = next
        return false
    }

    func makeTrip(existingNames: [String], now: Date = .now) -> Trip {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAuto = typed.isEmpty
        return Trip(
            name: isAuto ? autoName(existingNames: existingNames) : typed,
            isNameAuto: isAuto,
            destinations: destinations,
            dates: dates,
            now: now
        )
    }
}
