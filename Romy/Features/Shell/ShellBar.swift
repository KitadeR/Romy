import SwiftUI

/// The menu bar 「ホーム／旅程／行きたい／準備」, the round ＋, and what the ＋ opens (Notion 02 §6-3, §6-6).
/// The ＋ and the three buttons share one `GlassEffectContainer`, each with a `glassEffectID`, so the buttons grow
/// out of the ＋ and melt back into it (Apple, "Applying Liquid Glass to custom views"). The bar stays outside it.
/// The container's spacing equals the gaps: a larger one melts them together at rest, a smaller one makes the
/// buttons fade in where they stand instead of growing out of their neighbour.
/// The bar itself is the system's tab bar (2026-10-29), so its lens and the drag along it are iOS 26's own;
/// the ＋ follows the bar's middle, since the system decides where the bar sits.
/// It floats over the itinerary's sheet in a window of its own (`FloatingLayer`), so the sheet never moves it.
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
    /// Keeps the ＋ on the middle of the system's bar, which the system places on its own.
    @State private var plusAlignment = PlusAlignment()
    /// Where the bar and the ＋ are, for the floating window to take only the touches on them.
    @Environment(FloatingHitArea.self) private var hitArea: FloatingHitArea?
    @State private var barArea: CGRect = .null

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
                     sheet: .stay(day: dayForNewPlan)),
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
                        .background(PlusSlotMarker(alignment: plusAlignment))
                }
                // The ＋ and its buttons share their own container, apart from the bar, so the buttons can
                // only grow out of the ＋. They sit over the space kept for the ＋ and rise above it.
                .overlay(alignment: .bottomTrailing) {
                    PlusFollower(alignment: plusAlignment) {
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
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                barArea = $0
                reportHitArea()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, -18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onChange(of: isShowingAddMenu, initial: true) { _, _ in reportHitArea() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .plan(let day):
                AddPlanSheet(trip: trip, day: day, onAdded: onAdded)
                    .presentationDetents([.large])
            case .wish:
                AddPlanSheet(trip: trip)
                    .presentationDetents([.large])
            case .stay(let day):
                AddStaySheet(trip: trip, day: day, onAdded: onAdded)
                    .presentationDetents([.large])
            case .comingSoon(let title):
                ComingSoonView(title: title)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Bar

    /// Apple's own tab bar (試作 2026-10-29): a `TabView` with empty tabs, used only for its bar, so the lens,
    /// the drag along the bar and the glass are the system's. The tabs' contents stay in the shell's sheet.
    private var menuBar: some View {
        TabView(selection: Binding(get: { tab }, set: { choose($0) })) {
            ForEach(AppShell.Tab.allCases, id: \.self) { item in
                Tab(item.title, systemImage: item.symbol(selected: false), value: item) {
                    ClearTabBackground(alignment: plusAlignment)
                }
            }
        }
        .tint(Theme.ink)
        .frame(height: 68)
        // The system keeps its bar off the edges of the TabView; this undoes that, so the bar fills the space
        // beside the ＋ as the hand-made bar did. Measured on iPhone 17 Pro Max.
        .padding(.horizontal, -20)
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

    /// The bar with the ＋ (and the note over them), or the whole screen while the ＋ is open, so a tap
    /// anywhere closes it.
    private func reportHitArea() {
        hitArea?.rect = isShowingAddMenu ? .infinite : barArea
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

/// How far the ＋ moves up or down to sit on the middle of the system's bar (試作 2026-10-29). The system places
/// its bar itself and moves it with the sheet's animations, so both are measured from what is on the screen each
/// frame (`ClearTabBackground`). Only `PlusFollower` reads `shift`, so following the bar redraws the ＋ alone and
/// never the bar, which would move the bar again.
@Observable
final class PlusAlignment {
    var shift: CGFloat = 0
    /// The place kept for the ＋ beside the bar; it does not move when the ＋ does.
    @ObservationIgnored weak var slot: UIView?
}

private struct PlusFollower<Content: View>: View {
    let alignment: PlusAlignment
    @ViewBuilder let content: Content

    var body: some View {
        content.offset(y: alignment.shift)
    }
}

private struct PlusSlotMarker: UIViewRepresentable {
    let alignment: PlusAlignment

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        alignment.slot = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// The system's tab view lays a plain background under its tabs. Only its bar is used here, so that background
/// is made clear from inside the tab, up to the tab bar controller's own view (試作 2026-10-29).
/// Each frame it also measures where the bar's glass and the ＋'s place are on the screen and moves the ＋.
private struct ClearTabBackground: UIViewRepresentable {
    let alignment: PlusAlignment

    func makeUIView(context: Context) -> UIView { ClearingView(alignment: alignment) }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class ClearingView: UIView {
        let alignment: PlusAlignment
        private weak var tabBar: UITabBar?
        private var link: CADisplayLink?

        init(alignment: PlusAlignment) {
            self.alignment = alignment
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            link?.invalidate()
            link = nil
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var view = superview
                while let current = view {
                    current.backgroundColor = .clear
                    if let controller = current.next as? UITabBarController {
                        tabBar = controller.tabBar
                        break
                    }
                    view = current.superview
                }
                let link = CADisplayLink(target: self, selector: #selector(measure))
                link.add(to: .main, forMode: .common)
                self.link = link
            }
        }

        /// The bar's glass (the system's platter inside the tab bar, or the tab bar itself) against the ＋'s place,
        /// both as they are drawn this frame, so the ＋ moves with the bar while the sheet animates. The distance
        /// on the screen is turned back into the ＋'s own points, since the sheet may scale the bar (`barFit`).
        @objc private func measure() {
            guard let tabBar, let window = tabBar.window, let slot = alignment.slot, slot.window === window,
                  slot.bounds.height > 0 else { return }
            let glass = tabBar.subviews.first { String(describing: type(of: $0)).contains("Platter") } ?? tabBar
            let bar = Self.drawn(glass, in: window)
            let place = Self.drawn(slot, in: window)
            guard place.height > 0 else { return }
            let shift = (bar.midY - place.midY) / (place.height / slot.bounds.height)
            if abs(shift - alignment.shift) > 0.25 { alignment.shift = shift }
        }

        private static func drawn(_ view: UIView, in window: UIWindow) -> CGRect {
            let layer = view.layer.presentation() ?? view.layer
            return layer.convert(layer.bounds, to: window.layer.presentation() ?? window.layer)
        }
    }
}
