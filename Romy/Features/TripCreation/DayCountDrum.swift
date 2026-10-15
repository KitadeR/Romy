import SwiftUI

/// Numbers-only drum with 「日間」 fixed beside it; the number stays in the card's center (Figma 32:2).
struct DayCountDrum: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...30

    @State private var dragStep = 0

    var body: some View {
        VStack(spacing: 4) {
            neighbor(value - 1)
            Text("\(value)")
                .font(Theme.latin(44, .bold))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(value: Double(value)))
                .frame(width: 120, height: 76)
                .background(Capsule().fill(Theme.fill))
            neighbor(value + 1)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .center) {
            Text("日間")
                .font(Theme.jp(22, .bold))
                .foregroundStyle(Theme.ink)
                .offset(x: 105)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { drag in
                    let step = Int((-drag.translation.height / 36).rounded())
                    if step != dragStep {
                        set(value + step - dragStep)
                        dragStep = step
                    }
                }
                .onEnded { _ in dragStep = 0 }
        )
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel("日数")
        .accessibilityValue("\(value)日間")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + 1)
            case .decrement: set(value - 1)
            @unknown default: break
            }
        }
    }

    private func neighbor(_ number: Int) -> some View {
        Text(range.contains(number) ? "\(number)" : " ")
            .font(Theme.latin(28, .medium))
            .foregroundStyle(Theme.faint)
            .frame(height: 35)
            .onTapGesture { set(number) }
    }

    private func set(_ number: Int) {
        let clamped = min(max(number, range.lowerBound), range.upperBound)
        guard clamped != value else { return }
        withAnimation(.snappy) { value = clamped }
    }
}
