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

    /// The longest name a person can give; longer ones are cut.
    static let longestName = 40

    /// The name after the person edits it (Notion 02 §1, agreed 2026-10-07: 「旅行名は作成後も変更できる」).
    /// A blank name goes back to the automatic one, as when the trip was made; any other name is the person's own,
    /// so it is kept when destinations are added later. `existingNames` are those of the other trips.
    static func edited(
        _ input: String, destinations: [Destination], dates: TripDates, existingNames: [String], calendar: Calendar
    ) -> (name: String, isAuto: Bool) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let name = autoName(
                destinations: destinations, dates: dates, existingNames: existingNames, calendar: calendar
            )
            return (name, true)
        }
        return (String(trimmed.prefix(longestName)), false)
    }
}
