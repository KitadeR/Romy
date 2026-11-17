import SwiftUI

struct SceneReplacementSheet: View {
    let model: ActionSceneModel
    let option: SceneOption
    let index: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var results: SceneAlternatives?
    @State private var selected: String?
    @State private var revision = 0
    @State private var expired = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("現在の立ち寄り先").font(.caption).foregroundStyle(.secondary)
                    Text(option.way.steps[index].title).font(Theme.jp(19, .bold))
                    Divider()
                    if let results {
                        ForEach(results.choices) { choice in
                            Button { selected = choice.id } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(choice.place.name).font(Theme.jp(16, .bold))
                                        Text(difference(from: option.way, to: choice.way))
                                            .font(.subheadline)
                                        if !choice.way.fits {
                                            Text("\(choice.way.shortfallMinutes)分足りません").font(.caption)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: selected == choice.id ? "checkmark.circle.fill" : "circle")
                                }
                                .frame(minHeight: 48).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(!choice.way.fits)
                            .accessibilityAddTraits(selected == choice.id ? .isSelected : [])
                            Divider()
                        }
                        if results.incomplete {
                            Text("一部の場所や経路を取得できませんでした。")
                            Button("もう一度探す") { revision += 1 }
                        } else if results.choices.isEmpty {
                            Text("今の条件に合う別の立ち寄り先が見つかりませんでした。")
                        }
                    } else {
                        ProgressView("近くの店と徒歩経路を調べています")
                    }
                    if expired { Text("案が更新されました。詳細から選び直してください。") }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .navigationTitle(option.way.steps[index].kind == .eat ? "別の食事先" : "別のカフェ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                let choice = results?.choices.first { $0.id == selected }
                Button("この店に変更") {
                    if let choice, model.replace(choice) {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        dismiss()
                    } else {
                        expired = true
                    }
                }
                .buttonStyle(.glassProminent).buttonSizing(.flexible).controlSize(.large)
                .tint(Theme.ink).disabled(choice == nil || expired || option.isUnavailable).padding()
            }
            .sensoryFeedback(.selection, trigger: selected) { _, new in new != nil }
            .task(id: revision) {
                results = nil
                selected = nil
                let found = await model.replacements(for: option, at: index)
                if !Task.isCancelled { results = found }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func difference(from original: SceneWay, to alternative: SceneWay) -> String {
        let walk = delta(alternative.walkMinutes - original.walkMinutes)
        let rest = delta(alternative.sitMinutes - original.sitMinutes)
        return "徒歩\(walk) ・ 休憩\(rest)"
    }

    private func delta(_ minutes: Int) -> String {
        if minutes == 0 { return "は同じ" }
        return minutes > 0 ? "＋\(minutes)分" : "−\(-minutes)分"
    }
}
