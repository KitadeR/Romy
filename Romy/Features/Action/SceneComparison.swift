import MapKit
import SwiftUI

/// The map with the ways floating over it. Nothing sits under the cards (2026-11-19, るわさん「このお店のことと
/// LookAroundだけ表示するべき」); notices appear above them only while there is something to say.
struct SceneComparison<Header: View, Notice: View>: View {
    let model: ActionSceneModel
    let input: SceneInput
    @Binding var position: MapCameraPosition
    let open: (String) -> Void
    @ViewBuilder let header: () -> Header
    @ViewBuilder let notice: () -> Notice
    @State private var cardID: String?
    /// The height the cards and notices cover, kept clear when the map frames the ways.
    @State private var overlayHeight: CGFloat = 0
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
                        cards(width: geometry.size.width).padding(.vertical, 12)
                        notice().padding(.horizontal, 16)
                    }
                }
            } else {
                ZStack(alignment: .bottom) {
                    map
                        .safeAreaPadding(.bottom, overlayHeight)
                        .safeAreaInset(edge: .top, spacing: 0) { header().padding(12) }
                        .ignoresSafeArea(.container, edges: .bottom)
                    VStack(spacing: 10) {
                        notice().padding(.horizontal, 16)
                        cards(width: geometry.size.width)
                    }
                    .padding(.bottom, 8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { overlayHeight = $0 }
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
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(model.ways.enumerated()), id: \.element.id) { index, option in
                    SceneWayCard(option: option,
                                 position: model.ways.count > 1 ? "候補\(model.ways.count)件中\(index + 1)件目" : "") {
                        select(option.id)
                        cardID = option.id
                        open(option.id)
                    }
                    .frame(width: max(1, width - (model.ways.count > 1 ? 64 : 32)))
                    .id(option.id)
                    // 「1 / 2」は出さず、隣のカードの端で横にあると伝える。読み上げでは件数と移動を残す。
                    .accessibilityAdjustableAction { direction in
                        let target = direction == .increment ? index + 1 : index - 1
                        guard model.ways.indices.contains(target) else { return }
                        let id = model.ways[target].id
                        select(id)
                        withAnimation(reduceMotion ? nil : .snappy) { cardID = id }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .safeAreaPadding(.horizontal, model.ways.count > 1 ? 32 : 16)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: $cardID, anchor: .center)
        .onScrollPhaseChange { _, phase in
            // 停止した一枚だけを選ぶ。ドラッグ中に経由したカードで地図や触覚を切り替えない。
            if phase == .idle, let cardID { select(cardID) }
        }
    }

    private func select(_ id: String) {
        if id != currentID { selectionFeedback += 1 }
        model.selectedID = id
    }
}
