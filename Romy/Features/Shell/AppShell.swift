import SwiftData
import SwiftUI

/// One trip at a time: menu bar 「ホーム／旅程／行きたい／準備」 and a separate round ＋ (Notion 02 §6-3).
/// The bar stays the same in Plan, Action and Memories; only the contents change.
/// The bar itself is `ShellBar` (Liquid Glass, decided 2026-10-15). The itinerary is Apple's sheet over a map,
/// which covers the bottom of the screen, so there the bar is drawn inside that sheet.
struct AppShell: View {
    let trip: Trip

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
        /// Search a place to save with ♥ in 「行きたい」.
        case wish
        case comingSoon(String)

        var id: String {
            switch self {
            case .plan(let day): "plan-\(day ?? 0)"
            case .wish: "wish"
            case .comingSoon(let title): title
            }
        }
    }

    /// The dark note with 「元に戻す」: after adding a plan (Notion 02 §6-6, Figma 15-9), after marking one
    /// 済み or taking the mark off (Notion 02 §6-5), and after deleting one (Notion 02 §6-6). It lasts about 5 seconds.
    struct ShellNote: Equatable {
        let id = UUID()
        let message: String
        let kind: ShellNoteKind

        static func == (lhs: ShellNote, rhs: ShellNote) -> Bool { lhs.id == rhs.id }
    }

    @Environment(\.modelContext) private var modelContext
    @State private var tab: Tab = .home
    @State private var itineraryTab: ItineraryTab = .all
    @State private var isShowingAddMenu = false
    @State private var isCreatingTrip = false
    @State private var location = LocationProvider()
    @State private var sheet: AddSheet?
    @State private var note: ShellNote?
    @State private var highlighted: UUID?
    /// Travel times between plans; kept here so they stay when the tab changes.
    @State private var travel = TravelTimes()

    /// 旅程の日のタブからはその日、それ以外は未定 (Notion 02 §6-6 「入れる日」). Action's 「今日」 comes with the Action Home.
    private var dayForNewPlan: Int? {
        tab == .itinerary ? itineraryTab.dayForNewPlan : nil
    }

    var body: some View {
        // One sheet stays up on every tab (like Find My), so the menu bar inside it never changes layer:
        // on the itinerary it has three heights over the map, on the other tabs it is full height.
        ItineraryView(
            trip: trip,
            selection: $itineraryTab,
            highlighted: highlighted,
            isShowingAddMenu: isShowingAddMenu,
            isActive: tab == .itinerary,
            isCreatingTrip: $isCreatingTrip,
            onAdd: { sheet = .plan(day: $0) },
            onToggleDone: toggleDone,
            travel: travel,
            onDelete: delete,
            note: note,
            onUndo: undo,
            onWishAdded: noteAdded,
            bar: { bar },
            otherDetents: otherDetents,
            otherKey: tab.title,
            other: { otherTab($0) },
            background: { cover($0) }
        )
        .onChange(of: tab) { _, new in if new == .itinerary || new == .wishlist { location.start() } }
        .task(id: note?.id) {
            guard note != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) {
                note = nil
                highlighted = nil
            }
        }
    }

    /// What the sheet shows on the tabs other than the itinerary.
    @ViewBuilder
    private func otherTab(_ actions: HomeActions) -> some View {
        switch tab {
        case .home:
            PlanHomeSheet(
                trip: trip,
                actions: actions,
                onAddPlans: { sheet = .plan(day: nil) },
                onOpenUndecided: {
                    itineraryTab = .undecided
                    tab = .itinerary
                }
            )
        case .wishlist:
            wishlist(actions)
        case .preparation:
            ComingSoonView(title: tab.title)
        case .itinerary:
            EmptyView()
        }
    }

    private func wishlist(_ actions: HomeActions) -> some View {
        var wishActions = actions
        wishActions.search = { sheet = .wish }
        wishActions.removeWish = removeWish
        let isAction = TripPhase(dates: trip.dates, today: .now) == .action
        return WishlistSheet(trip: trip, isAction: isAction, location: location.location, actions: wishActions)
    }

    /// The heights the sheet rests at on each tab other than the itinerary; the first is where it opens.
    private var otherDetents: [PresentationDetent] {
        switch tab {
        case .home: [.fraction(0.65), .large]
        case .wishlist: [SheetHeights.middle, SheetHeights.small, SheetHeights.low, .large]
        case .itinerary, .preparation: [.large]
        }
    }

    /// What stands behind the sheet where the itinerary has its map: Home's cover, or nothing.
    @ViewBuilder
    private func cover(_ actions: HomeActions) -> some View {
        if tab == .home {
            PlanHomeCover(trip: trip, actions: actions)
        } else if tab == .wishlist {
            WishlistMap(trip: trip)
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

    /// Opens the itinerary on the day the plan went to and outlines it for a moment (Figma 15-9).
    private func showAdded(_ item: ItineraryItem) {
        itineraryTab = item.day.map { .day($0) } ?? .undecided
        tab = .itinerary
        highlighted = item.id
        withAnimation(.snappy) {
            note = ShellNote(
                message: ItineraryDays.addedMessage(title: item.title, day: item.day), kind: .added(item)
            )
        }
    }

    /// Marks a plan 済み, or takes the mark off, and offers 「元に戻す」 (Notion 02 §6-5).
    private func toggleDone(_ item: ItineraryItem) {
        let previous = item.doneAt
        item.doneAt = previous == nil ? .now : nil
        try? modelContext.save()
        withAnimation(.snappy) {
            note = ShellNote(
                message: ItineraryDays.doneMessage(title: item.title, isDone: item.doneAt != nil),
                kind: .markChanged(item, previous: previous)
            )
        }
    }

    /// Deletes a plan and offers 「元に戻す」 (Notion 02 §6-6). The order of the other plans is left as it is, so
    /// bringing the plan back puts it in the same place.
    private func delete(_ item: ItineraryItem) {
        let snapshot = item.snapshot()
        let message = ItineraryDays.deletedMessage(title: item.title)
        modelContext.delete(item)
        try? modelContext.save()
        withAnimation(.snappy) {
            note = ShellNote(message: message, kind: .deleted(snapshot))
        }
    }

    /// A plan was added from 「行きたい」: the tab stays, and 「元に戻す」 is offered.
    private func noteAdded(_ item: ItineraryItem) {
        withAnimation(.snappy) {
            note = ShellNote(
                message: ItineraryDays.addedMessage(title: item.title, day: item.day), kind: .added(item)
            )
        }
    }

    /// Takes a place out of 「行きたい」 and offers 「元に戻す」.
    private func removeWish(_ wish: WishPlace) {
        let snapshot = wish.snapshot()
        modelContext.delete(wish)
        try? modelContext.save()
        withAnimation(.snappy) {
            note = ShellNote(message: "「\(snapshot.title)」を行きたいから外しました", kind: .wishRemoved(snapshot))
        }
    }

    private func undo(_ note: ShellNote) {
        switch note.kind {
        case .added(let item):
            modelContext.delete(item)
        case .markChanged(let item, let previous):
            item.doneAt = previous
        case .deleted(let snapshot):
            let restored = ItineraryItem.restored(from: snapshot)
            modelContext.insert(restored)
            restored.trip = trip
        case .wishRemoved(let snapshot):
            let restored = WishPlace.restored(from: snapshot)
            modelContext.insert(restored)
            restored.trip = trip
        }
        try? modelContext.save()
        withAnimation(.snappy) {
            self.note = nil
            highlighted = nil
        }
    }
}

/// What a note's 「元に戻す」 takes back.
enum ShellNoteKind {
    case added(ItineraryItem)
    /// The mark the plan had before, to put back.
    case markChanged(ItineraryItem, previous: Date?)
    /// The plan as it was, to bring back.
    case deleted(ItineraryItemSnapshot)
    /// The saved place as it was, to bring back to 「行きたい」.
    case wishRemoved(WishSnapshot)
}
