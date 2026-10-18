import SwiftUI

/// The menu bar 「ホーム／旅程／行きたい／準備」, the round ＋, and what the ＋ opens (Notion 02 §6-3, §6-6).
/// The ＋ and the three buttons share one `GlassEffectContainer`, each with a `glassEffectID`, so the buttons grow
/// out of the ＋ and melt back into it (Apple, "Applying Liquid Glass to custom views"). The bar stays outside it.
/// The container's spacing equals the gaps: a larger one melts them together at rest, a smaller one makes the
/// buttons fade in where they stand instead of growing out of their neighbour.
/// The selected tab has a glass lens that slides between tabs.
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
    @Namespace private var lens

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
                    noteView(note).transition(.move(edge: .bottom).combined(with: .opacity))
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

    private var menuBar: some View {
        HStack(spacing: 0) {
            ForEach(AppShell.Tab.allCases, id: \.self) { item in
                Button {
                    setAddMenu(false)
                    withAnimation(.bouncy(duration: 0.35)) { tab = item }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.symbol(selected: tab == item))
                            .font(.system(size: 18, weight: .semibold))
                            .frame(height: 22)
                        Text(item.title).font(Theme.jp(10, tab == item ? .bold : .medium))
                    }
                    .foregroundStyle(tab == item ? Theme.ink : Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background {
                        if tab == item {
                            Capsule()
                                .fill(Theme.ink.opacity(0.08))
                                .matchedGeometryEffect(id: "lens", in: lens)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 68)
        .glassEffect(.regular.interactive(), in: .capsule)
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

    // MARK: - After adding

    private func noteView(_ note: AppShell.ShellNote) -> some View {
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

/// A tab shrinks a little while pressed, so a tap is felt even before the lens moves.
private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.bouncy(duration: 0.25), value: configuration.isPressed)
    }
}
