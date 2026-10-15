import SwiftUI

/// 「日付を決める」 (Notion 02 §4・§5): the same calendar as trip creation, moving the trip up to fixed dates.
/// From a day count, picking the start fills in that many days, and the end can still be moved.
struct DecideDatesSheet: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date?
    @State private var end: Date?

    private let calendar = Calendar.current
    private let text = DateText(calendar: .current, holidays: .bundled)
    private var today: Date { calendar.startOfDay(for: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("いつ行く？").font(Theme.jp(24, .bold)).foregroundStyle(Theme.ink).padding(.top, 24)

            RangeCalendarView(calendar: calendar, today: today, start: start, end: end) { day in
                withAnimation(.snappy) { tap(day) }
            }

            if let start {
                let last = end ?? start
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(text.range(start, last)).font(Theme.jp(18, .bold)).foregroundStyle(Theme.ink)
                    Text("\(text.dayCount(start, last))日間").font(Theme.jp(14, .medium)).foregroundStyle(Theme.secondary)
                }
            }

            Spacer()

            Button(action: decide) {
                Text("決める")
                    .font(Theme.jp(17, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(Theme.ink))
            }
            .buttonStyle(.plain)
            .opacity(start == nil ? 0.3 : 1)
            .disabled(start == nil)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .background(Theme.surface.ignoresSafeArea())
    }

    /// Day count: the first tap is the start and fills the days; later taps after it move the end.
    /// Undecided: first tap is the start, the next tap the end (same as trip creation).
    private func tap(_ day: Date) {
        if case .days(let count) = trip.dates {
            if let start, day > start {
                end = day
            } else {
                start = day
                end = calendar.date(byAdding: .day, value: count - 1, to: day)
            }
            return
        }
        if let start, end == nil, day >= start {
            end = day
        } else {
            start = day
            end = nil
        }
    }

    private func decide() {
        guard let start else { return }
        trip.dates = .range(start: start, end: end ?? start)
        trip.moveItemsPastLastDay()
        dismiss()
    }
}
