import SwiftUI

/// The itinerary tab (Notion 02 §6-3, §6-5, §6-6; Figma page 6 124:2 and 「16.」).
/// The map sits behind; the itinerary is Apple's sheet over it with three heights, and the map stays touchable
/// at the small and middle heights (`presentationBackgroundInteraction`, like Apple Maps).
/// The sheet covers the bottom of the screen, so the menu bar and ＋ are drawn inside it.
/// The time column, reordering, moving plans and 済み come next (Notion 05).
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
    @ViewBuilder let bar: () -> Bar

    @State private var isShowingTrips = false
    @State private var isDecidingDates = false
    /// Set by 「新しい旅行を作る」; creation opens once the trip list has closed.
    @State private var createAfterTrips = false
    @State private var isAddingDestinations = false
    @State private var isSheetPresented = true
    @State private var detent: PresentationDetent = Self.middle

    /// Small: name, caption and tabs above the menu bar. Middle: the map keeps the top 30% (Figma 124:2).
    private static var small: PresentationDetent { .height(300) }
    private static var middle: PresentationDetent { .fraction(0.7) }

    private let text = DateText(calendar: .current, holidays: .bundled)
    private var days: ItineraryDays { ItineraryDays(dates: trip.dates, text: text) }
    private var hasDates: Bool { trip.dates != .undecided }

    var body: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let fullHeight = geometry.size.height + insets.top + insets.bottom
            ItineraryMap(
                trip: trip,
                selection: selection,
                visibleFraction: 0.3,
                aspect: geometry.size.width / fullHeight,
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay { bar() }
        .sheet(isPresented: $isAddingDestinations) {
            AddDestinationsSheet(trip: trip)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $isShowingTrips, onDismiss: openCreationIfAsked) {
            AllTripsSheet(current: trip) { createAfterTrips = true }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isDecidingDates) {
            DecideDatesSheet(trip: trip)
                .presentationDetents([.large])
        }
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
        VStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    RouteRow(origin: items[index - 1], destination: item, isOnADay: day != nil)
                }
                ItineraryCard(
                    item: item, number: index + 1, color: Theme.dayColor(day), isHighlighted: item.id == highlighted
                )
            }
        }
    }

    /// Empty day: a dashed box that opens adding with this day already chosen (Notion 02 §6-6, 案A).
    private func addBox(_ title: String, day: Int?) -> some View {
        Button { onAdd(day) } label: {
            Label(title, systemImage: "plus")
                .font(Theme.jp(14, .bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.faint, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// A plan card: number in the day's color, name, and the kind (Figma 124:2).
/// Opening the plan's detail sheet comes with the detail sheet (Notion 05).
struct ItineraryCard: View {
    let item: ItineraryItem
    let number: Int
    let color: Color
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(Theme.latin(12, .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(color))
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(Theme.jp(16, .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let label = item.kind.label {
                    Text(label)
                        .font(Theme.jp(11, .bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.fill))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isHighlighted ? Theme.ink : Theme.line, lineWidth: isHighlighted ? 2 : 1)
        )
        .animation(.easeOut(duration: 0.3), value: isHighlighted)
    }
}
