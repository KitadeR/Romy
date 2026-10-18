import SwiftUI

/// The itinerary tab (Notion 02 §6-3, §6-5, §6-6; Figma page 6 124:2 and 「16.」).
/// The map sits behind; the itinerary is Apple's sheet over it with three heights, and the map stays touchable
/// at the small and middle heights (`presentationBackgroundInteraction`, like Apple Maps).
/// The sheet covers the bottom of the screen, so the menu bar and ＋ are drawn inside it.
/// In Action (the day before the trip to its last day) today's plans get 済み marks, 今 and the painted
/// line (Notion 02 §6-5). A plan opens its detail inside the same sheet (`PlanDetailView`).
struct ItineraryView<Bar: View>: View {
    let trip: Trip
    @Binding var selection: ItineraryTab
    /// The plan just added; its card is outlined for a moment (Figma 15-9).
    let highlighted: UUID?
    /// The ＋ menu needs room above the bar, so the sheet rises to the middle height when it opens.
    let isShowingAddMenu: Bool
    let onCreateTrip: () -> Void
    /// Opens 「行きたい所・予定を追加」 with the day it goes to (nil = 未定).
    let onAdd: (Int?) -> Void
    /// Marks a plan 済み, or takes the mark off; the shell offers 「元に戻す」.
    let onToggleDone: (ItineraryItem) -> Void
    /// Deletes a plan; the shell offers 「元に戻す」.
    let onDelete: (ItineraryItem) -> Void
    /// The shell's note (済み, 削除), shown over a plan's detail, where the menu bar is not.
    let note: AppShell.ShellNote?
    let onUndo: (AppShell.ShellNote) -> Void
    @ViewBuilder let bar: () -> Bar

    @State private var isShowingTrips = false
    @State private var isDecidingDates = false
    /// Set by 「新しい旅行を作る」; creation opens once the trip list has closed.
    @State private var createAfterTrips = false
    @State private var isAddingDestinations = false
    @State private var editingTime: EditingTime?
    @State private var moving: ItineraryItem?
    /// The plan whose detail is open (Notion 02 §6-6); nil shows the itinerary.
    @State private var detailID: UUID?

    private struct EditingTime: Identifiable {
        let item: ItineraryItem
        let slot: DaySchedule.Slot
        var id: UUID { item.id }
    }
    @State private var isSheetPresented = true
    @State private var detent: PresentationDetent = Self.middle

    /// Small: name, caption and tabs above the menu bar. Middle: the map keeps the top 30% (Figma 124:2).
    private static var small: PresentationDetent { .height(300) }
    private static var middle: PresentationDetent { .fraction(0.7) }

    private let text = DateText(calendar: .current, holidays: .bundled)
    private var days: ItineraryDays { ItineraryDays(dates: trip.dates, text: text) }
    private var hasDates: Bool { trip.dates != .undecided }
    private var isAction: Bool { TripPhase(dates: trip.dates, today: .now, calendar: text.calendar) == .action }
    /// The day of the trip that today is; 今 and スキップ exist only there.
    private var todayNumber: Int? { trip.dates.dayNumber(on: .now, calendar: text.calendar) }
    private var detailItem: ItineraryItem? {
        detailID.flatMap { id in trip.items.first { $0.id == id } }
    }

    var body: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let fullHeight = geometry.size.height + insets.top + insets.bottom
            ItineraryMap(
                trip: trip,
                selection: selection,
                visibleFraction: 0.3,
                aspect: geometry.size.width / fullHeight,
                selectedID: detailID,
                onSelect: openDetail(id:),
                onAddDestination: { isAddingDestinations = true }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isSheetPresented) {
            sheet
                .presentationDetents([Self.small, Self.middle, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: Self.middle))
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.surface)
                .presentationCornerRadius(28)
                .interactiveDismissDisabled()
        }
        .onChange(of: isShowingAddMenu) { _, isShowing in
            if isShowing, detent == Self.small { withAnimation(.snappy) { detent = Self.middle } }
        }
        .onChange(of: trip.dates) { _, _ in keepSelectionInRange() }
        .onAppear(perform: keepSelectionInRange)
    }

    // MARK: - Sheet

    /// Everything shown inside Apple's sheet. Sheets opened from here are attached here, because a view
    /// behind a sheet cannot present another one.
    private var sheet: some View {
        Group {
            if let item = detailItem {
                detail(for: item)
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The detail has its own buttons at the bottom, so the menu bar is only drawn with the list.
        .overlay { if detailItem == nil { bar() } }
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
        let slot = day == nil
            ? nil : trip.schedule(of: plans, on: days.date(of: day), calendar: text.calendar).slot(for: item.id)
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
            onToggleDone: { onToggleDone(item) },
            onDelete: {
                detailID = nil
                onDelete(item)
            }
        )
    }

    /// Opens a plan's detail; it needs room, so a small sheet rises to the middle height.
    private func openDetail(_ item: ItineraryItem) {
        withAnimation(.snappy) {
            detailID = item.id
            if detent == Self.small { detent = Self.middle }
        }
    }

    private func openDetail(id: UUID) {
        if let item = trip.items.first(where: { $0.id == id }) { openDetail(item) }
    }

    /// 経路 opens Apple Maps from the plan before (Plan) or from where the person is (Action).
    private func openRoute(to item: ItineraryItem) {
        guard let destination = RouteLink.mapItem(item) else { return }
        let origin = trip.routeOrigin(for: item, isAction: isAction).flatMap { RouteLink.mapItem($0) }
        RouteLink.open(to: destination, from: origin)
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

    /// The cards of a day. The dot of 今 follows the clock, so the list is drawn again every 30 seconds.
    private func cards(_ items: [ItineraryItem], day: Int?) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            cardList(items, day: day, now: context.date)
        }
    }

    private func cardList(_ items: [ItineraryItem], day: Int?, now: Date) -> some View {
        // 未定 has no order of visits, so no times; a day shows them (Notion 02 §6-5).
        let schedule = day == nil ? nil : trip.schedule(of: items, on: days.date(of: day), calendar: text.calendar)
        let nowMinutes = Trip.minutes(of: now, on: now, calendar: text.calendar) ?? 0
        // 済み marks only in Action, and only on days (未定 has no order of visits).
        let progress = isAction && day != nil
            ? DayProgress(
                plans: items.map { DayProgress.Input(id: $0.id, isDone: $0.doneAt != nil) },
                isToday: day == todayNumber
            )
            : nil
        let paintsLine = progress != nil && day == todayNumber
        let color = Theme.dayColor(day)
        /// The line of one plan: painted up to 今 in Action's today, grey otherwise, none in 未定.
        func lineStyle(of item: ItineraryItem) -> TimeLineStyle? {
            guard day != nil else { return nil }
            guard paintsLine, let progress else { return .gray }
            let fraction = schedule?.slot(for: item.id)?.progress(at: nowMinutes) ?? 0
            return TimeLineStyle(progress.state(of: item.id), color: color, fraction: fraction)
        }
        return VStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    RouteRow(
                        origin: items[index - 1], destination: item, isOnADay: day != nil,
                        line: lineStyle(of: items[index - 1])?.forMove,
                        highlight: paintsLine && progress?.state(of: items[index - 1].id) == .now ? color : nil
                    )
                }
                let slot = schedule?.slot(for: item.id)
                ItineraryRow(
                    item: item, number: index + 1, color: color,
                    isHighlighted: item.id == highlighted, slot: slot,
                    progress: progress?.state(of: item.id), line: lineStyle(of: item),
                    onTapTime: { if let slot { editingTime = EditingTime(item: item, slot: slot) } },
                    onToggleDone: { onToggleDone(item) }
                )
                .onTapGesture { openDetail(item) }
                // Long press lifts the card; dropping it on another plan puts it in that plan's place.
                .draggable(item.id.uuidString)
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = ids.first, let dragged = trip.items.first(where: { $0.id.uuidString == id }) else {
                        return false
                    }
                    withAnimation(.snappy) { trip.reorder(dragged, onto: item) }
                    return true
                }
            }
        }
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
        onCreateTrip()
    }
}
