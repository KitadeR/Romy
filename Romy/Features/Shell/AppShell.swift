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

    @State private var tab: Tab = .home
    @State private var isAdding = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:
                    PlanHomeView(trip: trip, onCreateTrip: onCreateTrip, onAddPlans: { isAdding = true })
                case .itinerary, .wishlist, .preparation:
                    ComingSoonView(title: tab.title)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            GlassEffectContainer(spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    menuBar
                    Button { isAdding = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 64, height: 64)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("追加")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
        .sheet(isPresented: $isAdding) {
            ComingSoonView(title: "予定を追加")
                .presentationDetents([.medium])
        }
    }

    private var menuBar: some View {
        HStack {
            ForEach(Tab.allCases, id: \.self) { item in
                Button { tab = item } label: {
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
}
