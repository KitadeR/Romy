import SwiftUI

/// The vertical line joining the times in the left column (Notion 02 §6-5 「縦の線＝今の線」).
/// In Action it is painted in the day's color up to 今 and dotted from 今 to the next plan; otherwise it is grey.
/// The dot of 今 moves down the plan with the time and stops at its bottom edge.
enum TimeLineStyle {
    case solid(Color)
    /// The move after 今 up to the next plan: dotted, without a dot of its own.
    case dotted(Color)
    /// 今: painted down to the dot (`fraction` of the way through the plan), dotted below it.
    case progress(Color, fraction: Double)
    case gray

    /// The style of the move row after a plan: the line goes on, but the dot stays with the plan.
    var forMove: TimeLineStyle {
        if case .progress(let color, _) = self { .dotted(color) } else { self }
    }

    /// Style for a plan in Action's day, or for its move row after it. `fraction` is how far the time is
    /// through the plan; it is only used for 今.
    init(_ state: DayProgress.State, color: Color, fraction: Double = 0) {
        switch state {
        case .done, .skipped: self = .solid(color)
        case .now: self = .progress(color, fraction: fraction)
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
    /// The dot moves between these distances from the top and the bottom of the card.
    static let dotInset: CGFloat = 17

    static func dotY(fraction: Double, rowHeight: CGFloat) -> CGFloat {
        let bottom = max(dotInset, rowHeight - dotInset)
        return dotInset + CGFloat(min(max(fraction, 0), 1)) * (bottom - dotInset)
    }
}

struct TimeLine: View {
    let style: TimeLineStyle

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height + TimeLineLayout.reach
            ZStack {
                switch style {
                case .solid(let color):
                    stroke(color, from: 0, to: height, dotted: false)
                case .gray:
                    stroke(Theme.line, from: 0, to: height, dotted: false)
                case .dotted(let color):
                    stroke(color, from: 0, to: height, dotted: true)
                case .progress(let color, let fraction):
                    let dotY = TimeLineLayout.dotY(fraction: fraction, rowHeight: geometry.size.height)
                    stroke(color, from: 0, to: dotY, dotted: false)
                    stroke(color, from: dotY, to: height, dotted: true)
                    Circle()
                        .fill(color)
                        .frame(width: 9, height: 9)
                        .position(x: TimeLineLayout.lineX + 1, y: dotY)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func stroke(_ color: Color, from top: CGFloat, to bottom: CGFloat, dotted: Bool) -> some View {
        Path { path in
            path.move(to: CGPoint(x: TimeLineLayout.lineX + 1, y: top))
            path.addLine(to: CGPoint(x: TimeLineLayout.lineX + 1, y: bottom))
        }
        .stroke(
            color,
            style: StrokeStyle(lineWidth: 2, lineCap: dotted ? .round : .butt, dash: dotted ? [0.1, 5] : [])
        )
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
