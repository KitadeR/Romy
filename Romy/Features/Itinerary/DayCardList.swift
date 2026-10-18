import SwiftUI

/// The cards of one day (or of 未定) with the moves between them (Notion 02 §6-3, §6-5).
/// The dot of 今 follows the clock, so the list is drawn again every 30 seconds.
struct DayCardList: View {
    let trip: Trip
    let items: [ItineraryItem]
    /// Nil for 未定.
    let day: Int?
    let days: ItineraryDays
    let isAction: Bool
    let todayNumber: Int?
    let highlighted: UUID?
    let travel: TravelTimes
    let calendar: Calendar
    let onEditTime: (ItineraryItem, DaySchedule.Slot) -> Void
    let onToggleDone: (ItineraryItem) -> Void
    let onOpen: (ItineraryItem) -> Void

    /// The moves between plans that have a place; their times are asked of MapKit once.
    private var moves: [TravelMove] {
        guard day != nil else { return [] }
        return zip(items, items.dropFirst()).compactMap { TravelTimes.move(from: $0, to: $1) }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            list(now: context.date)
        }
        .task(id: moves) { await travel.load(moves) }
    }

    private func list(now: Date) -> some View {
        // 未定 has no order of visits, so no times; a day shows them (Notion 02 §6-5).
        let schedule = day == nil ? nil : trip.schedule(
            of: items, on: days.date(of: day), calendar: calendar,
            travelMinutes: { travel.minutes(from: $0, to: $1) }
        )
        let nowMinutes = Trip.minutes(of: now, on: now, calendar: calendar) ?? 0
        // 済み marks only in Action, and only on days (未定 has no order of visits).
        let progress = isAction && day != nil
            ? DayProgress(
                plans: items.map { DayProgress.Input(id: $0.id, isDone: $0.doneAt != nil) },
                isToday: day == todayNumber
            )
            : nil
        let paintsLine = progress != nil && day == todayNumber
        let color = Theme.dayColor(day)
        /// The line of one plan: painted up to 今 in Action's today, grey otherwise, none in 未定.
        func lineStyle(of item: ItineraryItem) -> TimeLineStyle? {
            guard day != nil else { return nil }
            guard paintsLine, let progress else { return .gray }
            let fraction = schedule?.slot(for: item.id)?.progress(at: nowMinutes) ?? 0
            return TimeLineStyle(progress.state(of: item.id), color: color, fraction: fraction)
        }
        return VStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    RouteRow(
                        origin: items[index - 1], destination: item, isOnADay: day != nil, travel: travel,
                        line: lineStyle(of: items[index - 1])?.forMove,
                        highlight: paintsLine && progress?.state(of: items[index - 1].id) == .now ? color : nil
                    )
                }
                let slot = schedule?.slot(for: item.id)
                ItineraryRow(
                    item: item, number: index + 1, color: color,
                    isHighlighted: item.id == highlighted, slot: slot,
                    progress: progress?.state(of: item.id), line: lineStyle(of: item),
                    onTapTime: { if let slot { onEditTime(item, slot) } },
                    onToggleDone: { onToggleDone(item) }
                )
                .onTapGesture { onOpen(item) }
                // Long press lifts the card; dropping it on another plan puts it in that plan's place.
                .draggable(item.id.uuidString)
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = ids.first, let dragged = trip.items.first(where: { $0.id.uuidString == id }) else {
                        return false
                    }
                    withAnimation(.snappy) { trip.reorder(dragged, onto: item) }
                    return true
                }
            }
        }
    }
}
