import SwiftUI

/// The menu bar 「ホーム／旅程／行きたい／準備」, the round ＋, and what the ＋ opens (Notion 02 §6-3, §6-6).
/// The ＋ and the three buttons share one `GlassEffectContainer`, each with a `glassEffectID`, so the buttons grow
/// out of the ＋ and melt back into it (Apple, "Applying Liquid Glass to custom views"). The bar stays outside it.
/// The container's spacing equals the gaps: a larger one melts them together at rest, a smaller one makes the
/// buttons fade in where they stand instead of growing out of their neighbour.
/// The selected tab has a glass lens (`GlassLens`) that slides between tabs; a finger can pick it up and drag it
/// along the bar, and it settles on the nearest tab when let go, as in iOS 26's tab bar.
/// It is drawn by the shell, and inside the itinerary's sheet so it stays at the bottom of the screen there too.
struct ShellBar: View {
    @Binding var tab: AppShell.Tab
    @Binding var isShowingAddMenu: Bool
    @Binding var sheet: AppShell.AddSheet?
    @Binding var note: AppShell.ShellNote?
    let trip: Trip
    /// The day a plan added from the ＋ goes to (Notion 02 §6-6 「入れる日」).
    let dayForNewPlan: Int?
    let onAdded: (ItineraryItem) -> Void
    let onUndo: (AppShell.ShellNote) -> Void

    @Namespace private var glass
    /// Where a finger is along the bar while it touches it; nil when it does not.
    @State private var touchX: CGFloat?

    private struct MenuItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let sheet: AppShell.AddSheet
    }

    private var menuItems: [MenuItem] {
        [
            MenuItem(id: "stay", title: "宿", detail: "どこに泊まる？", symbol: "bed.double",
                     sheet: .comingSoon("宿を追加")),
            MenuItem(id: "move", title: "移動", detail: "新幹線・そのほか", symbol: "tram",
                     sheet: .comingSoon("移動を追加")),
            MenuItem(id: "plan", title: "行きたい所・予定", detail: "場所を探す・名前だけでも",
                     symbol: "smallcircle.filled.circle", sheet: .plan(day: dayForNewPlan))
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isShowingAddMenu {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { setAddMenu(false) }
                    .transition(.opacity)
            }

            VStack(alignment: .trailing, spacing: 12) {
                if let note {
                    ShellNoteView(note: note, onUndo: onUndo)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(alignment: .center, spacing: 12) {
                    menuBar
                    Color.clear.frame(width: 64, height: 64)
                }
                // The ＋ and its buttons share their own container, apart from the bar, so the buttons can
                // only grow out of the ＋. They sit over the space kept for the ＋ and rise above it.
                .overlay(alignment: .bottomTrailing) {
                    GlassEffectContainer(spacing: 12) {
                        VStack(alignment: .trailing, spacing: 12) {
                            if isShowingAddMenu {
                                ForEach(menuItems) { item in
                                    menuButton(item)
                                }
                            }
                            plusButton
                        }
                    }
                    .fixedSize()
                    .padding(.bottom, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .plan(let day):
                AddPlanSheet(trip: trip, day: day, onAdded: onAdded)
                    .presentationDetents([.large])
            case .comingSoon(let title):
                ComingSoonView(title: title)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Bar

    private static let barPadding: CGFloat = 6

    private var menuBar: some View {
        GeometryReader { geometry in
            let tabs = AppShell.Tab.allCases
            let track = LensTrack(
                count: tabs.count, itemWidth: (geometry.size.width - Self.barPadding * 2) / CGFloat(tabs.count)
            )
            let chosen = tabs.firstIndex(of: tab) ?? 0
            let lensOffset = touchX.map { track.followingOffset(at: $0) } ?? track.offset(of: chosen)
            // While touched, the tab under the finger is the one shown as chosen.
            let shown = touchX.map { track.index(at: $0) } ?? chosen
            ZStack(alignment: .leading) {
                GlassLens()
                    .frame(width: track.itemWidth, height: 56)
                    .offset(x: lensOffset)
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { index, item in
                        tabLabel(item, isShown: index == shown)
                            .frame(width: track.itemWidth)
                    }
                }
            }
            .padding(.horizontal, Self.barPadding)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let position = value.location.x - Self.barPadding
                        // The lens comes to the finger once, then follows it without a delay.
                        if touchX == nil {
                            withAnimation(.snappy(duration: 0.18)) { touchX = position }
                        } else {
                            touchX = position
                        }
                    }
                    .onEnded { value in
                        let index = track.index(at: value.location.x - Self.barPadding)
                        withAnimation(.bouncy(duration: 0.4)) {
                            touchX = nil
                            choose(tabs[index])
                        }
                    }
            )
        }
        .frame(height: 68)
        .glassEffect(.regular, in: .capsule)
        .sensoryFeedback(.selection, trigger: tab)
    }

    private func tabLabel(_ item: AppShell.Tab, isShown: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: item.symbol(selected: isShown))
                .font(.system(size: 18, weight: .semibold))
                .frame(height: 22)
            Text(item.title).font(Theme.jp(10, isShown ? .bold : .medium))
        }
        .foregroundStyle(isShown ? Theme.ink : Theme.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(tab == item ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { choose(item) }
    }

    private func choose(_ item: AppShell.Tab) {
        setAddMenu(false)
        tab = item
    }

    private var plusButton: some View {
        Button { setAddMenu(!isShowingAddMenu) } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .rotationEffect(.degrees(isShowingAddMenu ? 45 : 0))
                .frame(width: 64, height: 64)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID("plus", in: glass)
        .accessibilityLabel(isShowingAddMenu ? "閉じる" : "追加")
    }

    // MARK: - ＋ menu

    /// Three large buttons grow out of the ＋ (Notion 02 §6-6, Figma 15-1).
    private func menuButton(_ item: MenuItem) -> some View {
        Button {
            setAddMenu(false)
            sheet = item.sheet
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.surface))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(Theme.jp(16, .bold)).foregroundStyle(Theme.ink)
                    Text(item.detail).font(Theme.jp(11, .medium)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 20)
            .padding(.vertical, 10)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID(item.id, in: glass)
        .glassEffectTransition(.matchedGeometry)
        // Grows from the ＋'s corner, so the glass is seen coming out of the ＋.
        .transition(.scale(scale: 0.2, anchor: .bottomTrailing).combined(with: .opacity))
    }

    private func setAddMenu(_ isShowing: Bool) {
        withAnimation(.bouncy(duration: 0.4, extraBounce: 0.05)) { isShowingAddMenu = isShowing }
    }

}

/// The dark note with 「元に戻す」, over the menu bar or over a plan's detail.
struct ShellNoteView: View {
    let note: AppShell.ShellNote
    let onUndo: (AppShell.ShellNote) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(note.message)
                .font(Theme.jp(14, .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("元に戻す") { onUndo(note) }
                .font(Theme.jp(14, .bold))
                .foregroundStyle(Theme.undo)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.ink))
    }
}
