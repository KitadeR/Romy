import Foundation

/// Name given when the person leaves the trip name blank (Notion 02 §1, agreed 2026-10-07).
enum TripNaming {
    /// - Destinations: the first two short names, e.g. 「京都・大阪旅行」. None: 「新しい旅行」.
    /// - Same name already used: add the month when dates are fixed, otherwise a number.
    static func autoName(
        destinations: [Destination], dates: TripDates, existingNames: [String], calendar: Calendar
    ) -> String {
        let base = destinations.isEmpty
            ? "新しい旅行"
            : destinations.prefix(2).map(\.shortName).joined(separator: "・") + "旅行"
        let taken = Set(existingNames)
        guard taken.contains(base) else { return base }

        if case .range(let start, _) = dates {
            let withMonth = "\(base)（\(calendar.component(.month, from: start))月）"
            if !taken.contains(withMonth) { return withMonth }
        }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }
}
