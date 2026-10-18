import SwiftUI

/// The vertical line joining the times in the left column (Notion 02 §6-5 「縦の線＝今の線」).
/// In Action it is painted in the day's color up to 今 and dotted from 今 to the next plan; otherwise it is grey.
enum TimeLineStyle {
    case solid(Color)
    case dotted(Color)
    case gray

    /// Style for a plan in Action's day, or for its move row after it.
    init(_ state: DayProgress.State, color: Color) {
        switch state {
        case .done, .skipped: self = .solid(color)
        case .now: self = .dotted(color)
        case .upcoming: self = .gray
        }
    }
}

/// Where the line runs: in the gap between the time column and the card.
enum TimeLineLayout {
    static let timeWidth: CGFloat = 46
    static let rowSpacing: CGFloat = 10
    /// Left edge of the 2pt line.
    static let lineX: CGFloat = timeWidth + 4
    /// The plans are 6pt apart, so a segment reaches 6pt below its row to meet the next one.
    static let reach: CGFloat = 6
}

struct TimeLine: View {
    let style: TimeLineStyle

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height + TimeLineLayout.reach
            Path { path in
                path.move(to: CGPoint(x: 1, y: 0))
                path.addLine(to: CGPoint(x: 1, y: height))
            }
            .stroke(
                color,
                style: StrokeStyle(lineWidth: 2, lineCap: isDotted ? .round : .butt, dash: isDotted ? [0.1, 5] : [])
            )
            .offset(x: TimeLineLayout.lineX)
        }
        .allowsHitTesting(false)
    }

    private var color: Color {
        switch style {
        case .solid(let color), .dotted(let color): color
        case .gray: Theme.line
        }
    }

    private var isDotted: Bool {
        if case .dotted = style { true } else { false }
    }
}

/// One plan with its times in the left column (Notion 02 §6-5 時刻の見せ方, Figma 124:2).
/// Start on top, end below; a guess is light, a fixed time is dark with a lock. Tapping the times opens the time sheet.
struct ItineraryRow: View {
    let item: ItineraryItem
    let number: Int
    let color: Color
    let isHighlighted: Bool
    /// Nil in 未定, which has no times.
    let slot: DaySchedule.Slot?
    /// Nil outside Action, which has no 済み marks.
    let progress: DayProgress.State?
    /// Nil in 未定, which has no line.
    let line: TimeLineStyle?
    let onTapTime: () -> Void
    let onToggleDone: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: TimeLineLayout.rowSpacing) {
            if let slot {
                timeColumn(slot)
            }
            ItineraryCard(
                item: item, number: number, color: color, isHighlighted: isHighlighted,
                progress: progress, onToggleDone: onToggleDone
            )
        }
        .background { if let line, slot != nil { TimeLine(style: line) } }
        .overlay(alignment: .topLeading) {
            // The dot sits at the start of 今 (it moves down with the clock later; Notion 05).
            if progress == .now, slot != nil {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .offset(x: TimeLineLayout.lineX + 1 - 4.5, y: 17)
                    .allowsHitTesting(false)
            }
        }
    }

    private func timeColumn(_ slot: DaySchedule.Slot) -> some View {
        Button(action: onTapTime) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 2) {
                    if slot.isFixed { Image(systemName: "lock.fill").font(.system(size: 8)) }
                    Text(DaySchedule.clock(slot.startMinutes))
                }
                .font(Theme.latin(12, slot.isFixed ? .bold : .medium))
                .foregroundStyle(slot.isFixed ? Theme.ink : Theme.secondary)
                Text(DaySchedule.clock(slot.endMinutes))
                    .font(Theme.latin(11, .medium))
                    .foregroundStyle(Theme.faint)
            }
            .frame(width: TimeLineLayout.timeWidth, alignment: .trailing)
            .padding(.top, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(DaySchedule.clock(slot.startMinutes))から\(DaySchedule.clock(slot.endMinutes))、時刻を変える")
    }
}
