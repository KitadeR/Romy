import SwiftUI

/// A plan card: number in the day's color, name, and the kind (Figma 124:2).
/// In Action it also shows where the plan stands (Notion 02 §6-5): 今 is lifted and bigger with a circle to mark it
/// 済み, 済み is small and light with a ✓ that takes the mark off, スキップ is light with a dotted outline.
/// Opening the plan's detail sheet comes with the detail sheet (Notion 05).
struct ItineraryCard: View {
    let item: ItineraryItem
    let number: Int
    let color: Color
    let isHighlighted: Bool
    /// Nil outside Action.
    var progress: DayProgress.State?
    var onToggleDone: () -> Void = {}

    private var isNow: Bool {
        progress == .now
    }

    private var isDone: Bool {
        progress == .done
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(Theme.latin(12, .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(color))
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(Theme.jp(isNow ? 17 : isDone ? 14 : 16, .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let label = item.kind.label, !isDone {
                    Text(label)
                        .font(Theme.jp(11, .bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.fill))
                }
            }
            mark
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isNow ? 18 : isDone ? 9 : 14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .overlay(outline)
        .shadow(color: .black.opacity(isNow ? 0.14 : 0), radius: 10, y: 4)
        .opacity(progress == .skipped ? 0.5 : isDone ? 0.55 : 1)
        .animation(.easeOut(duration: 0.3), value: isHighlighted)
        .animation(.snappy, value: progress)
    }

    /// The circle on 今 and the ✓ on 済み; nothing on the others (Notion 02 §6-5).
    @ViewBuilder
    private var mark: some View {
        switch progress {
        case .now:
            Button(action: onToggleDone) {
                Circle()
                    .strokeBorder(Theme.ink, lineWidth: 2)
                    .frame(width: 28, height: 28)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -8)
            .padding(.trailing, -8)
            .accessibilityLabel("\(item.title)を済みにする")
        case .done:
            Button(action: onToggleDone) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -12)
            .padding(.trailing, -8)
            .accessibilityLabel("\(item.title)の済みを取り消す")
        case .skipped, .upcoming, nil:
            EmptyView()
        }
    }

    private var outline: some View {
        RoundedRectangle(cornerRadius: 18)
            .strokeBorder(
                isHighlighted || isNow ? Theme.ink : Theme.line,
                style: StrokeStyle(
                    lineWidth: isHighlighted ? 2 : 1, dash: progress == .skipped ? [4, 4] : []
                )
            )
    }
}
