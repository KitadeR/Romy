import SwiftUI

/// The itinerary tab (Notion 02 §6-3, §6-5, §6-6; Figma page 6 124:2 and 「16.」).
/// The map sits behind; the itinerary is Apple's sheet over it with three heights, and the map stays touchable
/// at the small and middle heights (`presentationBackgroundInteraction`, like Apple Maps).
/// The sheet covers the bottom of the screen, so the menu bar and ＋ are drawn inside it.
/// In Action (the day before the trip to its last day) today's plans get 済み marks, 今 and the painted
/// line (Notion 02 §6-5). A plan opens its detail inside the same sheet (`PlanDetailView`).
struct ItineraryView<Bar: View, Other: View, Back: View>: View {
    let trip: Trip
    @Binding var selection: ItineraryTab
    /// The plans just added; their cards are outlined for a moment (Figma 15-9, 27).
    let highlighted: Set<UUID>
    /// The ＋ menu needs room above the bar, so the sheet rises to the middle height when it opens.
    let isShowingAddMenu: Bool
    /// True while the itinerary tab is chosen; on the other tabs the same sheet shows `other` at full height.
    let isActive: Bool
    /// Raised by 「新しい旅行を作る」; trip creation is presented from inside the sheet, which is always up.
    @Binding var isCreatingTrip: Bool
    /// Opens 「行きたい所・予定を追加」 with the day it goes to (nil = 未定).
    let onAdd: (Int?) -> Void
    /// Marks a plan 済み, or takes the mark off; the shell offers 「元に戻す」.
    let onToggleDone: (ItineraryItem) -> Void
    /// The travel times between plans (MapKit), kept while the app runs.
    let travel: TravelTimes
    /// Deletes a plan; the shell offers 「元に戻す」.
    let onDelete: (ItineraryItem) -> Void
    /// The shell's note (済み, 削除), shown over a plan's detail, where the menu bar is not.
    let note: AppShell.ShellNote?
    let onUndo: (AppShell.ShellNote) -> Void
    /// A plan was added from 「行きたい」 (the shell offers 「元に戻す」).
    let onWishAdded: (ItineraryItem) -> Void
    @ViewBuilder let bar: () -> Bar
    /// What the sheet shows on the other tabs (ホーム／行きたい／準備), the heights it rests at there, and what
    /// stands behind it where the itinerary has its map (Home's cover).
    let otherDetents: [PresentationDetent]
    /// Names the tab shown in `other`, so each tab comes to its own first height instead of the last one's.
    let otherKey: String
    @ViewBuilder let other: (HomeActions) -> Other
    @ViewBuilder let background: (HomeActions) -> Back

    @State var isShowingTrips = false
    @State var isPickingPhoto = false
    @State var choosingWish: WishPlace?
    @State var routeRequest: RouteRequest?
    @State var isDecidingDates = false
    /// Set by 「新しい旅行を作る」; creation opens once the trip list has closed.
    @State private var createAfterTrips = false
    @State var isAddingDestinations = false
    @State private var editingTime: EditingTime?
    @State private var moving: ItineraryItem?
    @State var proposing: ActionOpportunity?
    /// The plan whose detail is open (Notion 02 §6-6); nil shows the itinerary.
    @State var detailID: UUID?

    private struct EditingTime: Identifiable {
        let item: ItineraryItem
        let slot: DaySchedule.Slot
        var id: UUID { item.id }
    }
    /// Raised without animation when the tab opens, so the sheet is there at once instead of sliding up each time.
    @State private var isSheetPresented = false
    /// Where the sheet's content is drawn on the screen, and the size it is laid out in. iOS 26 draws a sheet that
    /// is not full height a little smaller and off the screen's sides; the menu bar undoes that (`barFit`).
    @State var sheetFrame: CGRect = .zero
    @State var sheetLayout: CGSize = .zero
    @State var screen = ScreenMetrics()
    @State var otherDetent = OtherDetent()
    /// The itinerary's own height, kept while another tab holds the sheet at full height.
    @State var itineraryDetent: PresentationDetent = Self.middle

    private static var middle: PresentationDetent { SheetHeights.middle }

    let text = DateText(calendar: .current, holidays: .bundled)
    private var days: ItineraryDays { ItineraryDays(dates: trip.dates, text: text) }
    private var hasDates: Bool { trip.dates != .undecided }
    var isAction: Bool { TripPhase(dates: trip.dates, today: .now, calendar: text.calendar) == .action }
    /// The day of the trip that today is; 今 and スキップ exist only there.
    var todayNumber: Int? { trip.dates.dayNumber(on: .now, calendar: text.calendar) }
    var detailItem: ItineraryItem? {
        detailID.flatMap { id in trip.items.first { $0.id == id } }
    }

    var body: some View {
        ZStack {
            mapLayer
            if !isActive { background(homeActions) }
        }
        .background(Theme.base.ignoresSafeArea())
        .sheet(isPresented: $isSheetPresented) {
            sheet
                .presentationDetents(
                    isActive ? SheetHeights.all : Set(otherDetents), selection: detentSelection
                )
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(isActive || otherDetents.count > 1 ? .visible : .hidden)
                .presentationBackground(Theme.surface)
                .interactiveDismissDisabled()
        }
        .onChange(of: isShowingAddMenu) { _, isShowing in
            if isShowing, isActive, SheetHeights.isLow(detent) { withAnimation(.snappy) { detent = Self.middle } }
        }
        .onChange(of: trip.dates) { _, _ in keepSelectionInRange() }
        .onAppear {
            keepSelectionInRange()
            withTransaction(.instant) { isSheetPresented = true }
        }
    }

    // MARK: - Sheet

    /// Everything shown inside Apple's sheet. Sheets opened from here are attached here, because a view
    /// behind a sheet cannot present another one.
    private var sheet: some View {
        Group {
            if !isActive {
                other(homeActions)
            } else if let item = detailItem {
                detail(for: item)
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The detail has its own buttons at the bottom, so the menu bar is only drawn with the list.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { sheetFrame = $0 }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { sheetLayout = $0 }
        .overlay(alignment: .bottom) { if showsBar { barFade } }
        .overlay {
            if showsBar {
                bar()
                    .scaleEffect(barFit.scale, anchor: .bottom)
                    .offset(x: barFit.shiftX, y: barFit.shiftY)
            }
        }
        .sheet(isPresented: $isAddingDestinations) {
            AddDestinationsSheet(trip: trip)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $isShowingTrips, onDismiss: openCreationIfAsked) {
            AllTripsSheet(current: trip) { createAfterTrips = true }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $moving) { item in
            MoveSheet(trip: trip, item: item)
                .presentationDetents([.large])
        }
        .actionProposalSheet($proposing)
        .sheet(item: $editingTime) { editing in
            TimeSheet(item: editing.item, slot: editing.slot) { duration, fixed in
                editing.item.durationMinutes = duration
                editing.item.fixedStartMinutes = fixed
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isDecidingDates) {
            DecideDatesSheet(trip: trip)
                .presentationDetents([.large])
        }
        .tripPhotoPicker(isPresented: $isPickingPhoto, trip: trip)
        .routeChooser($routeRequest)
        .sheet(item: $choosingWish) { wish in
            WishDaySheet(trip: trip, wish: wish, onAdded: onWishAdded)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $isCreatingTrip) {
            TripCreationView { trip in trip.lastOpenedAt = .now }
                .presentationDetents([.large])
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
                .padding(.top, 22)
            tabs
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Plan detail

    private func detail(for item: ItineraryItem) -> some View {
        let dayCount = ItineraryDays.count(of: trip.dates)
        let day = ItineraryDays.placement(of: item.day, dayCount: dayCount)
        let plans = trip.items(on: day)
        let schedule = day == nil ? nil : trip.schedule(
            of: plans, on: days.date(of: day), calendar: text.calendar,
            travelMinutes: { travel.minutes(from: $0, to: $1) }
        )
        let slot = schedule?.slot(for: item.id)
        return PlanDetailView(
            item: item,
            number: (plans.firstIndex { $0.id == item.id } ?? 0) + 1,
            dayCaption: day.map { days.caption(for: .day($0), hasDestination: true) } ?? "未定",
            color: Theme.dayColor(day),
            slot: slot,
            canMarkDone: isAction && day != nil,
            note: note,
            onUndo: onUndo,
            onClose: { withAnimation(.snappy) { detailID = nil } },
            onEditTime: { if let slot { editingTime = EditingTime(item: item, slot: slot) } },
            onMove: { moving = item },
            onSendToUndecided: { withAnimation(.snappy) { trip.move(item, toDay: nil) } },
            onRoute: { openRoute(to: item) },
            onSuggest: suggestion(for: item, day: day, plans: plans, schedule: schedule),
            onToggleDone: { onToggleDone(item) },
            onDelete: {
                detailID = nil
                onDelete(item)
            }
        )
    }

    /// Opens a plan's detail; it needs room, so a small sheet rises to the middle height.
    private func openDetail(_ item: ItineraryItem) {
        // The map has to stay in view: from the small or the large height the detail comes to the middle.
        withAnimation(.snappy) {
            detailID = item.id
            detent = Self.middle
        }
    }

    func openDetail(id: UUID) {
        if let item = trip.items.first(where: { $0.id == id }) { openDetail(item) }
    }

    /// 経路 opens the route (Apple Maps or Google Maps) from the plan before (Plan) or from where the person is (Action).
    private func openRoute(to item: ItineraryItem) {
        let before = trip.routeOrigin(for: item, isAction: isAction)
        let mode = before.flatMap { TravelTimes.move(from: $0, to: item)?.mode }
        guard let request = RouteRequest.route(to: item, from: before, mode: mode) else { return }
        RouteLink.start(request, chooser: $routeRequest)
    }

    // MARK: - Header and tabs

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { isShowingTrips = true } label: {
                HStack(spacing: 4) {
                    Text(trip.name).font(Theme.jp(22, .bold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
            .accessibilityHint("すべての旅行を開く")
            Text(days.caption(for: selection, hasDestination: !trip.destinations.isEmpty))
                .font(Theme.jp(13, .medium))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 20)
    }

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("全体", tab: .all, dot: nil)
                chip("未定", tab: .undecided, dot: nil)
                if hasDates {
                    ForEach(days.days, id: \.number) { day in
                        chip(days.tabLabel(day), tab: .day(day.number), dot: Theme.dayColor(day.number))
                    }
                } else {
                    Button { isDecidingDates = true } label: {
                        Text("＋ 日付を決める")
                            .font(Theme.jp(13, .bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Capsule().fill(Theme.surface))
                            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, tab: ItineraryTab, dot: Color?) -> some View {
        let isSelected = selection == tab
        return Button {
            withAnimation(.snappy) { selection = tab }
        } label: {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
                Text(title).font(Theme.jp(13, .bold))
            }
            .foregroundStyle(isSelected ? Theme.surface : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(isSelected ? Theme.ink : Theme.fill))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

}

extension ItineraryView {
    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !hasDates {
            // Only 全体 and 未定 exist; both show 未定 (Figma 16-5, 16-6).
            dayList(nil, emptyLabel: "予定を追加（未定に入ります）")
        } else {
            switch selection {
            case .all:
                VStack(alignment: .leading, spacing: 22) {
                    let undecided = trip.items(on: nil)
                    if !undecided.isEmpty {
                        section(title: "未定", day: nil, items: undecided)
                    }
                    ForEach(days.days, id: \.number) { day in
                        section(title: days.tabLabel(day), day: day.number, items: trip.items(on: day.number))
                    }
                }
            case .undecided:
                VStack(alignment: .leading, spacing: 14) {
                    if trip.items(on: nil).isEmpty {
                        Text("日を決めていない予定はここに入ります。あとで日に入れられます。")
                            .font(Theme.jp(13, .medium))
                            .foregroundStyle(Theme.secondary)
                    }
                    dayList(nil, emptyLabel: "未定に予定を追加")
                }
            case .day(let number):
                dayList(number, emptyLabel: "この日の予定を追加")
            }
        }
    }

    private func section(title: String, day: Int?, items: [ItineraryItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Theme.dayColor(day)).frame(width: 7, height: 7)
                Text(title).font(Theme.jp(14, .bold)).foregroundStyle(Theme.ink)
            }
            if items.isEmpty {
                addBox("追加", day: day)
            } else {
                cards(items, day: day)
            }
        }
    }

    @ViewBuilder
    private func dayList(_ day: Int?, emptyLabel: String) -> some View {
        let items = trip.items(on: day)
        if items.isEmpty {
            addBox(emptyLabel, day: day)
        } else {
            cards(items, day: day)
        }
    }

    private func cards(_ items: [ItineraryItem], day: Int?) -> some View {
        DayCardList(
            trip: trip, items: items, day: day, days: days, isAction: isAction, todayNumber: todayNumber,
            highlighted: highlighted, travel: travel, calendar: text.calendar,
            onEditTime: { editingTime = EditingTime(item: $0, slot: $1) },
            onToggleDone: onToggleDone,
            onOpen: openDetail
        )
    }

    /// Empty day: a dashed box that opens adding with this day already chosen (Notion 02 §6-6, 案A).
    private func addBox(_ title: String, day: Int?) -> some View {
        DashedAddBox(title: title) { onAdd(day) }
    }

    // MARK: - Helpers

    /// A day tab past the end (after the dates change) falls back to 全体.
    private func keepSelectionInRange() {
        if case .day(let number) = selection, number > ItineraryDays.count(of: trip.dates) {
            selection = .all
        }
    }

    private func openCreationIfAsked() {
        guard createAfterTrips else { return }
        createAfterTrips = false
        isCreatingTrip = true
    }
}
