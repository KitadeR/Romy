import SwiftUI

/// Month calendar that opens in place under the quick date chips (Figma page 6, 227:341).
/// Shared later by the "decide the dates" sheet (Notion 02 §5).
struct RangeCalendarView: View {
    let calendar: Calendar
    let today: Date
    let start: Date?
    let end: Date?
    let onTap: (Date) -> Void

    @State private var month: Date

    init(calendar: Calendar, today: Date, start: Date?, end: Date?, onTap: @escaping (Date) -> Void) {
        self.calendar = calendar
        self.today = today
        self.start = start
        self.end = end
        self.onTap = onTap
        let anchor = start ?? today
        _month = State(initialValue: calendar.date(from: calendar.dateComponents([.year, .month], from: anchor))!)
    }

    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(monthTitle)
                    .font(Theme.jp(15, .bold))
                Spacer()
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(!canGoBack)
                    .accessibilityLabel("前の月")
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("次の月")
            }
            .foregroundStyle(Theme.ink)
            .buttonStyle(.plain)
            .padding(.trailing, 4)

            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { day in
                    Text(day)
                        .font(Theme.jp(11, .medium))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
            }

            ForEach(weeks.indices, id: \.self) { index in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        dayCell(weeks[index][column])
                    }
                }
            }
        }
    }

    private var monthTitle: String {
        let parts = calendar.dateComponents([.year, .month], from: month)
        return "\(parts.year ?? 0)年\(parts.month ?? 0)月"
    }

    private var canGoBack: Bool {
        month > calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
    }

    private func shiftMonth(_ value: Int) {
        withAnimation(.snappy) { month = calendar.date(byAdding: .month, value: value, to: month)! }
    }

    /// Rows of 7, Sunday first, nil for blank cells.
    private var weeks: [[Date?]] {
        let leading = calendar.component(.weekday, from: month) - 1
        let count = calendar.range(of: .day, in: .month, for: month)!.count
        var cells: [Date?] = Array(repeating: nil, count: leading)
        cells += (0..<count).map { calendar.date(byAdding: .day, value: $0, to: month) }
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        if let day {
            let isEdge = day == start || day == end
            let isInside = start.map { day > $0 } == true && end.map { day < $0 } == true
            let isPast = day < today
            Button { onTap(day) } label: {
                Text("\(calendar.component(.day, from: day))")
                    .font(Theme.jp(14, .bold))
                    .foregroundStyle(isEdge ? .white : (isPast ? Theme.faint : Theme.ink))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(
                        Capsule().fill(isEdge ? Theme.ink : (isInside ? Theme.rangeFill : .clear))
                    )
            }
            .buttonStyle(.plain)
            .disabled(isPast)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 34)
        }
    }
}
