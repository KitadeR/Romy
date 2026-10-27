import SwiftUI

/// 「いまどうする？」 (Figma 26-02・03・04; Notion 02 §6-4 2026-10-25・27): the person picks how they are with emoji tiles
/// (any number), and, when tired, how tired on a slider whose face and words change and whose feel grows stronger each
/// step up. 「一言そえる」 is not offered yet: free words need the AI (後半).
struct StateTilesSheet: View {
    /// The tiles chosen from the Home card's chips.
    let initial: Set<ActionState>
    /// 「この内容で探す」 with the states and, when tired, how tired.
    let onSearch: (Set<ActionState>, TiredStrength?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var states: Set<ActionState> = []
    @State private var strength: TiredStrength = .quite
    @State private var isAskingStrength = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if isAskingStrength { strengthPage } else { tilesPage }
            Spacer(minLength: 0)
            mainButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .background(Theme.surface.ignoresSafeArea())
        .onAppear { states = initial }
        .animation(.snappy, value: isAskingStrength)
    }

    private var header: some View {
        HStack {
            if isAskingStrength {
                Button { isAskingStrength = false } label: {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("状態を選び直す")
            }
            Text(isAskingStrength ? "どれくらい疲れた？" : "いまどうする？").font(Theme.jp(24, .bold))
            Spacer()
            Button("閉じる") { dismiss() }
                .font(Theme.jp(14, .bold))
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Capsule().fill(Theme.fill))
                .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.ink)
    }

    // MARK: - Tiles (26-02)

    private var tilesPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今の状態を選んでください（いくつでも）").font(Theme.jp(13, .medium)).foregroundStyle(Theme.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ActionState.allCases, id: \.self) { state in tile(state) }
            }
        }
    }

    private func tile(_ state: ActionState) -> some View {
        let isOn = states.contains(state)
        return Button {
            if isOn { states.remove(state) } else { states.insert(state) }
        } label: {
            VStack(spacing: 8) {
                Text(state.emoji).font(.system(size: 34))
                Text(state.label).font(Theme.jp(13, .bold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? .white : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(RoundedRectangle(cornerRadius: 18).fill(isOn ? Theme.ink : Color.white))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(isOn ? Theme.ink : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Strength (26-03・04)

    private var strengthPage: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(ActionState.allCases.filter(states.contains), id: \.self) { state in
                    Text("\(state.emoji) \(state.label)")
                        .font(Theme.jp(13, .bold))
                        .foregroundStyle(state == .tired ? .white : Theme.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(state == .tired ? Theme.ink : Theme.fill))
                }
                Spacer(minLength: 0)
            }
            Text(strength.emoji).font(.system(size: 88)).contentTransition(.opacity)
            Text(strength.phrase).font(Theme.jp(20, .bold)).foregroundStyle(Theme.ink)
            StrengthSlider(value: $strength)
            VStack(alignment: .leading, spacing: 6) {
                Text("この段だと").font(Theme.jp(12, .bold)).foregroundStyle(Theme.secondary)
                ForEach(strength.whatChanges, id: \.self) { line in
                    Text(line).font(Theme.jp(14, .medium)).foregroundStyle(Theme.ink)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.fill))
        }
        .sensoryFeedback(trigger: strength) { old, new in
            guard new > old else { return nil }
            let weight: SensoryFeedback.Weight = [.light, .medium, .heavy][new.impact.weight]
            return .impact(weight: weight, intensity: new.impact.intensity)
        }
    }

    // MARK: - Button

    /// 「次へ」 asks how tired when 疲れた is chosen; otherwise, and on the strength page, 「この内容で探す」.
    private var mainButton: some View {
        let asksStrength = !isAskingStrength && states.contains(.tired)
        return Button {
            if asksStrength {
                isAskingStrength = true
            } else {
                onSearch(states, states.contains(.tired) ? strength : nil)
            }
        } label: {
            Text(asksStrength ? "次へ" : "この内容で探す")
                .font(Theme.jp(17, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Capsule().fill(states.isEmpty ? Theme.faint : Theme.ink))
        }
        .buttonStyle(.plain)
        .disabled(states.isEmpty)
    }
}

/// Four steps on a line, with the names under them (Figma 26-03, Strava's labelled steps). Drag or tap a step.
private struct StrengthSlider: View {
    @Binding var value: TiredStrength

    private let steps = TiredStrength.allCases

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let width = geometry.size.width - 32
                let place = { (step: TiredStrength) in 16 + width * CGFloat(step.rawValue) / CGFloat(steps.count - 1) }
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line).frame(height: 4).padding(.horizontal, 16)
                    Capsule().fill(Theme.ink).frame(width: place(value) - 16, height: 4).padding(.leading, 16)
                    ForEach(steps, id: \.self) { step in
                        Circle().fill(step <= value ? Theme.ink : Theme.line).frame(width: 8, height: 8)
                            .position(x: place(step), y: 22)
                    }
                    Circle().fill(.white)
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                        .frame(width: 32, height: 32)
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                        .position(x: place(value), y: 22)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let ratio = (drag.location.x - 16) / max(width, 1)
                    let index = Int((ratio * CGFloat(steps.count - 1)).rounded())
                    let step = steps[min(max(index, 0), steps.count - 1)]
                    if step != value { withAnimation(.snappy) { value = step } }
                })
            }
            .frame(height: 44)
            HStack {
                ForEach(steps, id: \.self) { step in
                    Text(step.label)
                        .font(Theme.jp(12, step == value ? .bold : .medium))
                        .foregroundStyle(step == value ? Theme.ink : Theme.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("疲れの強さ")
        .accessibilityValue(value.label)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if let next = TiredStrength(rawValue: value.rawValue + 1) { value = next }
            case .decrement: if let previous = TiredStrength(rawValue: value.rawValue - 1) { value = previous }
            @unknown default: break
            }
        }
    }
}
