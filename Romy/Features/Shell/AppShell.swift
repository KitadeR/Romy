import SwiftData
import SwiftUI

/// One trip at a time: menu bar 「ホーム／旅程／行きたい／準備」 and a separate round ＋ (Notion 02 §6-3).
/// The bar stays the same in Plan, Action and Memories; only the contents change.
/// The bar itself is `ShellBar` (Liquid Glass, decided 2026-10-15). The itinerary is Apple's sheet over a map,
/// which covers the bottom of the screen, so there the bar is drawn inside that sheet.
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
                        isShowingAddMenu: isShowingAddMenu,
                        onCreateTrip: createTripFromItinerary,
                        onAdd: { sheet = .plan(day: $0) },
                        bar: { bar }
                    )
                case .wishlist, .preparation:
                    ComingSoonView(title: tab.title)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if tab != .itinerary {
                bar
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

    private var bar: ShellBar {
        ShellBar(
            tab: $tab,
            isShowingAddMenu: $isShowingAddMenu,
            sheet: $sheet,
            note: $note,
            trip: trip,
            dayForNewPlan: dayForNewPlan,
            onAdded: showAdded,
            onUndo: undo
        )
    }

    /// Trip creation is presented from the root, which cannot happen while the itinerary's sheet is up,
    /// so the itinerary closes first.
    private func createTripFromItinerary() {
        tab = .home
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            onCreateTrip()
        }
    }

    /// Opens the itinerary on the day the plan went to and outlines it for a moment (Figma 15-9).
    private func showAdded(_ item: ItineraryItem) {
        itineraryTab = item.day.map { .day($0) } ?? .undecided
        tab = .itinerary
        highlighted = item.id
        withAnimation(.snappy) {
            note = AddedNote(item: item, message: ItineraryDays.addedMessage(title: item.title, day: item.day))
        }
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
