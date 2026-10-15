import SwiftData
import SwiftUI

/// One trip at a time: menu bar 「ホーム／旅程／行きたい／準備」 and a separate round ＋ (Notion 02 §6-3).
/// The bar stays the same in Plan, Action and Memories; only the contents change.
/// Both are Apple's Liquid Glass (decided 2026-10-15), grouped so the two pieces of glass blend.
struct AppShell: View {
    let trip: Trip
    let onCreateTrip: () -> Void

    enum Tab: CaseIterable {
        case home, itinerary, wishlist, preparation

        var title: String {
            switch self {
            case .home: "ホーム"
            case .itinerary: "旅程"
            case .wishlist: "行きたい"
            case .preparation: "準備"
            }
        }

        func symbol(selected: Bool) -> String {
            switch self {
            case .home: selected ? "house.fill" : "house"
            case .itinerary: "list.bullet"
            case .wishlist: selected ? "heart.fill" : "heart"
            case .preparation: "checkmark"
            }
        }
    }

    /// What the ＋ opens (Notion 02 §6-6). 移動 and 宿 are built next; until then they say so.
    enum AddSheet: Identifiable {
        case plan(day: Int?)
        case comingSoon(String)

        var id: String {
            switch self {
            case .plan(let day): "plan-\(day ?? 0)"
            case .comingSoon(let title): title
            }
        }
    }

    /// The note after adding, with 「元に戻す」 (Notion 02 §6-6, Figma 15-9).
    struct AddedNote: Equatable {
        let item: ItineraryItem
        let message: String

        static func == (lhs: AddedNote, rhs: AddedNote) -> Bool { lhs.item.id == rhs.item.id }
    }

    @Environment(\.modelContext) private var modelContext
    @State private var tab: Tab = .home
    @State private var itineraryTab: ItineraryTab = .all
    @State private var isShowingAddMenu = false
    @State private var sheet: AddSheet?
    @State private var note: AddedNote?
    @State private var highlighted: UUID?

    /// 旅程の日のタブからはその日、それ以外は未定 (Notion 02 §6-6 「入れる日」). Action's 「今日」 comes with the Action Home.
    private var dayForNewPlan: Int? {
        tab == .itinerary ? itineraryTab.dayForNewPlan : nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:
                    PlanHomeView(
                        trip: trip,
                        onCreateTrip: onCreateTrip,
                        onAddPlans: { sheet = .plan(day: nil) },
                        onOpenUndecided: {
                            itineraryTab = .undecided
                            tab = .itinerary
                        }
                    )
                case .itinerary:
                    ItineraryView(
                        trip: trip,
                        selection: $itineraryTab,
                        highlighted: highlighted,
                        onCreateTrip: onCreateTrip,
                        onAdd: { sheet = .plan(day: $0) }
                    )
                case .wishlist, .preparation:
                    ComingSoonView(title: tab.title)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                if isShowingAddMenu {
                    addMenu.transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                }
                bar
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .plan(let day):
                AddPlanSheet(trip: trip, day: day, onAdded: showAdded)
                    .presentationDetents([.large])
            case .comingSoon(let title):
                ComingSoonView(title: title)
                    .presentationDetents([.medium])
            }
        }
        .task(id: note?.item.id) {
            guard note != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) {
                note = nil
                highlighted = nil
            }
        }
    }

    // MARK: - Bar

    private var bar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                menuBar
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
                .accessibilityLabel(isShowingAddMenu ? "閉じる" : "追加")
            }
        }
    }

    private var menuBar: some View {
        HStack {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    setAddMenu(false)
                    tab = item
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.symbol(selected: tab == item))
                            .font(.system(size: 18, weight: .semibold))
                            .frame(height: 22)
                        Text(item.title).font(Theme.jp(10, tab == item ? .bold : .medium))
                    }
                    .foregroundStyle(tab == item ? Theme.ink : Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 68)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    // MARK: - ＋

    /// Three large buttons float up from the ＋ (Notion 02 §6-6, Figma 15-1).
    private var addMenu: some View {
        VStack(alignment: .trailing, spacing: 10) {
            addMenuButton("宿", detail: "どこに泊まる？", symbol: "bed.double") {
                sheet = .comingSoon("宿を追加")
            }
            addMenuButton("移動", detail: "新幹線・そのほか", symbol: "tram") {
                sheet = .comingSoon("移動を追加")
            }
            addMenuButton("行きたい所・予定", detail: "場所を探す・名前だけでも", symbol: "smallcircle.filled.circle") {
                sheet = .plan(day: dayForNewPlan)
            }
        }
    }

    private func addMenuButton(
        _ title: String, detail: String, symbol: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            setAddMenu(false)
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.surface))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.jp(16, .bold)).foregroundStyle(Theme.ink)
                    Text(detail).font(Theme.jp(11, .medium)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 20)
            .padding(.vertical, 10)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func setAddMenu(_ isShowing: Bool) {
        withAnimation(.snappy) { isShowingAddMenu = isShowing }
    }

    // MARK: - After adding

    /// Opens the itinerary on the day the plan went to and outlines it for a moment (Figma 15-9).
    private func showAdded(_ item: ItineraryItem) {
        itineraryTab = item.day.map { .day($0) } ?? .undecided
        tab = .itinerary
        highlighted = item.id
        withAnimation(.snappy) {
            note = AddedNote(item: item, message: ItineraryDays.addedMessage(title: item.title, day: item.day))
        }
    }

    private func noteView(_ note: AddedNote) -> some View {
        HStack(spacing: 12) {
            Text(note.message)
                .font(Theme.jp(14, .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("元に戻す") { undo(note) }
                .font(Theme.jp(14, .bold))
                .foregroundStyle(Theme.undo)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.ink))
    }

    private func undo(_ note: AddedNote) {
        modelContext.delete(note.item)
        try? modelContext.save()
        withAnimation(.snappy) {
            self.note = nil
            highlighted = nil
        }
    }
}
