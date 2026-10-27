import SwiftUI

/// Action Home 「観光の時間」 (Figma 71:288, 26-01; Notion 02 §6-4 2026-10-27): shown instead of Plan Home on the days
/// of the trip. The cover behind the sheet carries the day and, big, where the person is; the sheet carries the plan
/// that is 今, 「いまどうする？」, the rest of today and tonight's stay. Nothing about the Shinkansen (保留, 2026-10-16).
struct ActionHomeCover: View {
    let trip: Trip
    let actions: HomeActions
    @Environment(LocationProvider.self) private var location
    @State private var here: String?

    private let text = DateText(calendar: .current, holidays: .bundled)
    private static let sky = [Color(hex: 0x7DB2E6), Color(hex: 0xC9B3C9), Color(hex: 0xEFB48E)]

    private var day: Int? {
        trip.dates.dayNumber(on: .now, calendar: text.calendar)
    }

    /// The ward is asked again only after moving about 500 m, not on every location update.
    private var lookUpKey: String? {
        location.location.map { "\(Int($0.coordinate.latitude * 200)),\(Int($0.coordinate.longitude * 200))" }
    }

    /// Where the person is; without it, where the plan that is 今 is, then the trip's destination
    /// (Notion 02 §6-4, 2026-10-08 案: 位置情報を許可しない人には旅程のその日の行き先).
    private var bigName: String {
        if let here {
            return ActionToday.shortArea(here)
        }
        let today = day.map { trip.items(on: $0) } ?? []
        if let area = today.first(where: { $0.doneAt == nil })?.area {
            return ActionToday.shortArea(area)
        }
        return trip.destinations.first?.name ?? trip.name
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: Self.sky, startPoint: .top, endPoint: .bottom)
                .frame(height: 420)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
            VStack(alignment: .leading, spacing: 4) {
                if let day {
                    Text(ItineraryDays(dates: trip.dates, text: text).caption(for: .day(day), hasDestination: true))
                        .font(Theme.jp(14, .medium))
                }
                PlanHomeTripName(name: trip.name, size: 18, action: actions.showTrips)
                Text(bigName)
                    .font(Theme.jp(56, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 26)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.15), radius: 6)
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .task { location.start() }
        .task(id: lookUpKey) {
            guard let coordinate = location.location?.coordinate else { return }
            here = await PlaceSearch.lookUpWard(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }
}

/// What slides over the Action cover.
struct ActionHomeSheet: View {
    let trip: Trip
    let actions: HomeActions
    let travel: TravelTimes
    let onToggleDone: (ItineraryItem) -> Void
    let onAddPlans: () -> Void
    /// Puts a confirmed way into the itinerary (段階6); nil once it is in.
    let onApplyScene: (SceneApply) -> SceneApply.Problem?
    /// After the proposal has closed: show the itinerary with the new plans.
    let onSceneApplied: () -> Void
    /// Raised by 「いまどうする？」 in 準備: opens the emoji tiles as the card here does.
    @Binding var askRequested: Bool

    /// The emoji tiles (段階4), then the proposal they open. The proposal waits for the tiles to close.
    @State private var asking: AskRequest?
    @State private var waitingProposal: SceneRequest?
    @State private var proposing: SceneRequest?
    @State private var applied = false

    private let text = DateText(calendar: .current, holidays: .bundled)

    private var today: ActionToday? {
        guard let day = trip.dates.dayNumber(on: .now, calendar: text.calendar) else { return nil }
        let plans = trip.items(on: day)
        let schedule = trip.schedule(
            of: plans, on: .now, calendar: text.calendar, travelMinutes: { travel.minutes(from: $0, to: $1) }
        )
        return ActionToday(plans: plans, day: day, schedule: schedule)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if actions.isExpanded {
                    PlanHomeTripName(name: trip.name, size: 22, action: actions.showTrips)
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 8)
                }
                if let today {
                    nowCard(today)
                    if let now = today.now, !today.remaining.isEmpty {
                        AskCard { asking = AskRequest(id: now.item.id, states: $0) }
                    }
                    if !today.remaining.isEmpty {
                        remaining(today)
                    }
                    if let stay = today.stay {
                        stayCard(stay)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.surface.ignoresSafeArea())
        .task(id: trip.items.count) { await loadTravel() }
        .onChange(of: askRequested, initial: true) { _, asked in if asked { openAskFromPreparation() } }
        .sheet(item: $asking, onDismiss: openWaitingProposal) { request in
            StateTilesSheet(initial: request.states) { states, strength in
                let plans = today.map { trip.items(on: $0.day).map { $0.snapshot() } } ?? []
                waitingProposal = SceneRequest(
                    id: request.id, plans: plans, states: states, strength: strength,
                    currentStartMinutes: today?.now?.slot.startMinutes
                )
                asking = nil
            }
            .presentationDetents([.large])
        }
        .sheet(item: $proposing, onDismiss: showApplied) { request in
            ActionSceneSheet(request: request) { change in
                let problem = onApplyScene(change)
                if problem == nil {
                    applied = true
                    proposing = nil
                }
                return problem
            }
            .presentationDetents([.large])
        }
    }

    /// 「いまどうする？」 pressed in 準備: the tiles open here for the plan that is 今, as the card would.
    private func openAskFromPreparation() {
        askRequested = false
        guard let today, let now = today.now, !today.remaining.isEmpty else { return }
        asking = AskRequest(id: now.item.id, states: [])
    }

    private func showApplied() {
        guard applied else { return }
        applied = false
        onSceneApplied()
    }

    private func openWaitingProposal() {
        proposing = waitingProposal
        waitingProposal = nil
    }

    /// The day's travel times, so the times here match the itinerary's.
    private func loadTravel() async {
        guard let day = today?.day else { return }
        let plans = trip.items(on: day)
        await travel.load(zip(plans, plans.dropFirst()).compactMap { TravelTimes.move(from: $0, to: $1) })
    }

    // MARK: - 今

    /// The black card: the plan that is 今 with its 済み circle; with nothing left, a free day.
    @ViewBuilder
    private func nowCard(_ today: ActionToday) -> some View {
        if let now = today.now {
            nowPlanCard(now)
        } else {
            freeDayCard
        }
    }

    private func nowPlanCard(_ now: ActionToday.Row) -> some View {
        HStack(spacing: 12) {
            Button { actions.openPlan(now.item.id) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(DaySchedule.clock(now.slot.startMinutes)) – \(DaySchedule.clock(now.slot.endMinutes))")
                        .font(Theme.latin(15, .medium))
                        .opacity(0.7)
                    Text(now.item.title).font(Theme.jp(22, .bold)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { onToggleDone(now.item) } label: {
                Circle().strokeBorder(.white, lineWidth: 2).frame(width: 32, height: 32)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(now.item.title)を済みにする")
            Button { actions.openPlan(now.item.id) } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(now.item.title)の詳細")
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.ink))
    }

    /// Nothing left today: 「今日は自由な日」 and adding a plan (Notion 02 §6-4, 2026-10-08 案).
    private var freeDayCard: some View {
        Button(action: onAddPlans) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日は自由な日").font(Theme.jp(13, .medium)).opacity(0.7)
                    Text("予定を足す").font(Theme.jp(22, .bold))
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white))
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 24).fill(Theme.ink))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 今日の残り・今夜の宿

    private func remaining(_ today: ActionToday) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日の残り").font(Theme.jp(13, .bold)).foregroundStyle(Theme.secondary).padding(.top, 4)
            ForEach(today.remaining, id: \.item.id) { row in
                Button { actions.openPlan(row.item.id) } label: {
                    HStack(spacing: 10) {
                        Circle().fill(Theme.dayColor(today.day)).frame(width: 7, height: 7)
                        Text(DaySchedule.clock(row.slot.startMinutes))
                            .font(Theme.latin(15, .bold))
                            .foregroundStyle(row.slot.isFixed ? Theme.ink : Theme.secondary)
                        Text(Self.line(for: row.item)).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 「ホテル（例）京都駅前 ・ チェックイン」: a stay that opens later says so.
    static func line(for item: ItineraryItem) -> String {
        item.kind == .stay && item.notBeforeMinutes != nil ? "\(item.title) ・ チェックイン" : item.title
    }

    private func stayCard(_ stay: ItineraryItem) -> some View {
        Button { actions.openPlan(stay.id) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今夜の宿").font(Theme.jp(12, .medium)).foregroundStyle(Theme.secondary)
                    Text(stay.title).font(Theme.jp(16, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.faint)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.fill))
        }
        .buttonStyle(.plain)
    }
}

/// The tiles to open, with the states already chosen from the Home card's chips.
private struct AskRequest: Identifiable {
    let id: UUID
    let states: Set<ActionState>
}

/// 「いまどうする？」 (Figma 26-01): right under the plan that is 今, with three states the person often has. The card
/// opens the emoji tiles; a chip opens them with that state chosen (疲れていても1タップ).
private struct AskCard: View {
    let onAsk: (Set<ActionState>) -> Void

    private static let chips: [ActionState] = [.tired, .heavyLuggage, .hungry]

    var body: some View {
        Button { onAsk([]) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("いまどうする？").font(Theme.jp(20, .bold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                }
                Text("次の予定までの過ごし方を、今の状態から探します")
                    .font(Theme.jp(13, .medium))
                    .foregroundStyle(Theme.secondary)
                HStack(spacing: 8) {
                    ForEach(Self.chips, id: \.self) { state in
                        Button { onAsk([state]) } label: {
                            Text("\(state.emoji) \(state.label)").font(Theme.jp(13, .bold))
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(Capsule().fill(Theme.fill))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.ink, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
