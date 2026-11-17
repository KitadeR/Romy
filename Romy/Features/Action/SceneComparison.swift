import MapKit
import SwiftUI

struct SceneComparison<Header: View, Footer: View>: View {
    let model: ActionSceneModel
    let input: SceneInput
    @Binding var position: MapCameraPosition
    let open: (String) -> Void
    @ViewBuilder let header: () -> Header
    @ViewBuilder let footer: () -> Footer
    @State private var cardID: String?
    @State private var selectionFeedback = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var currentID: String { model.selectedID ?? model.ways.first?.id ?? "" }

    var body: some View {
        GeometryReader { geometry in
            if typeSize.isAccessibilitySize || geometry.size.height < 520 {
                ScrollView {
                    VStack(spacing: 0) {
                        header().padding(12)
                        map.frame(height: 240)
                        cards(width: geometry.size.width)
                        footer()
                    }
                }
            } else {
                VStack(spacing: 0) {
                    map.safeAreaInset(edge: .top, spacing: 0) { header().padding(12) }
                    cards(width: geometry.size.width)
                    footer()
                }
            }
        }
        .background(Theme.base)
        .onAppear { cardID = currentID }
        .onChange(of: model.resultsVersion) { cardID = currentID }
        .sensoryFeedback(.selection, trigger: selectionFeedback)
    }

    private var map: some View {
        SceneMap(input: input, options: model.ways, selectedID: currentID, routes: model.routes,
                 position: $position) { id in
            select(id)
            withAnimation(reduceMotion ? nil : .snappy) { cardID = id }
        }
    }

    private func cards(width: CGFloat) -> some View {
        VStack(spacing: 2) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(model.ways) { option in
                        SceneWayCard(option: option) {
                            select(option.id)
                            cardID = option.id
                            open(option.id)
                        }
                        .frame(width: max(1, width - (model.ways.count > 1 ? 64 : 32)))
                        .id(option.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .safeAreaPadding(.horizontal, model.ways.count > 1 ? 32 : 16)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $cardID, anchor: .center)
            .onScrollPhaseChange { _, phase in
                // 停止した一枚だけを選ぶ。ドラッグ中に経由したカードで地図や触覚を切り替えない。
                if phase == .idle, let cardID { select(cardID) }
            }
            if model.ways.count > 1, let index = model.ways.firstIndex(where: { $0.id == currentID }) {
                Text("\(index + 1) / \(model.ways.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.actionSecondary)
                    .accessibilityLabel("候補\(model.ways.count)件中\(index + 1)件目")
                    .accessibilityAdjustableAction { direction in
                        let target = direction == .increment ? index + 1 : index - 1
                        guard model.ways.indices.contains(target) else { return }
                        let id = model.ways[target].id
                        select(id)
                        cardID = id
                    }
            }
        }
        .padding(.top, 10)
    }

    private func select(_ id: String) {
        if id != currentID { selectionFeedback += 1 }
        model.selectedID = id
    }
}
