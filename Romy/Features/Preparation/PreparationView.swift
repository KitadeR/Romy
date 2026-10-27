import SwiftUI

/// The 準備 tab, first half (Notion 02 §6-3 決定 2026-10-27, Figma 28): what still needs booking, in the order of the
/// trip, with only the thing to do now as the black card. The day before it is 「明日の準備」, on a day of the trip
/// 「今日の確認」. 持ち物 and the weather come later.
struct PreparationView: View {
    let trip: Trip
    let onOpen: (ItineraryItem) -> Void
    let onBook: (ItineraryItem) -> Void
    /// 「いまどうする？」: the same flow as the Action Home.
    let onAsk: () -> Void
    let onAddPlans: () -> Void

    private let text = DateText(calendar: .current, holidays: .bundled)
    private var days: ItineraryDays { ItineraryDays(dates: trip.dates, text: text) }

    var body: some View {
        let preparation = Preparation(trip: trip, calendar: text.calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(preparation)
                switch preparation.phase {
                case .day(let day): today(preparation, day: day)
                case .eve: eve(preparation)
                case .before, .after: beforeTrip(preparation)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.surface.ignoresSafeArea())
    }

    // MARK: - Phases

    private func header(_ preparation: Preparation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("準備").font(Theme.jp(30, .bold)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            Text(subtitle(preparation)).font(Theme.jp(14, .medium)).foregroundStyle(Theme.secondary)
        }
    }

    private func subtitle(_ preparation: Preparation) -> String {
        switch preparation.phase {
        case .day(let day): return "今日 \(days.caption(for: .day(day), hasDestination: true))"
        case .eve: return "明日 \(days.caption(for: .day(1), hasDestination: true)) から"
        case .before, .after:
            guard preparation.total > 0 else { return "予約が要る予定はまだありません" }
            let count = "予約 \(preparation.total)つ中\(preparation.booked.count)つ済み"
            if case .before(let left?) = preparation.phase, left > 0 { return "\(count) ・ 出発まで\(left)日" }
            return count
        }
    }

    @ViewBuilder
    private func beforeTrip(_ preparation: Preparation) -> some View {
        if preparation.total == 0 {
            empty
        } else {
            if let next = preparation.pending.first {
                label("今やること")
                bookCard(next, small: "\(Preparation.context(of: next, days: days)) ・ \(next.title)", rows: [])
            }
            if preparation.pending.count > 1 || !preparation.booked.isEmpty {
                label("出発まで")
            }
            ForEach(preparation.pending.dropFirst(), id: \.id) { pendingCard($0) }
            ForEach(preparation.booked, id: \.id) { bookedRow($0) }
        }
    }

    @ViewBuilder
    private func eve(_ preparation: Preparation) -> some View {
        label("明日の準備")
        let progress = "明日の準備 \(preparation.booked.count) / \(preparation.total)"
        if let next = preparation.pending.first {
            bookCard(next, small: progress, rows: ["\(Preparation.context(of: next, days: days)) ・ \(next.title)"])
        } else {
            blackCard {
                Text(preparation.total == 0 ? "明日の準備" : progress).font(Theme.jp(12, .medium)).opacity(0.7)
                Text(preparation.total == 0 ? "予約が要る予定はありません" : "明日の準備はOK")
                    .font(Theme.jp(22, .bold))
            }
        }
        ForEach(preparation.pending.dropFirst(), id: \.id) { pendingCard($0) }
        if !preparation.booked.isEmpty { label("予約済み") }
        ForEach(preparation.booked, id: \.id) { bookedRow($0) }
    }

    @ViewBuilder
    private func today(_ preparation: Preparation, day: Int) -> some View {
        label("今日の確認")
        blackCard {
            Text("今日の確認 ・ \(DaySchedule.clock(Trip.minutes(of: .now, on: .now, calendar: text.calendar) ?? 0))")
                .font(Theme.jp(12, .medium)).opacity(0.7)
            if preparation.checks.isEmpty {
                Text("今日は時刻の決まった予定はありません").font(Theme.jp(13)).opacity(0.85)
            }
            ForEach(Array(preparation.checks.enumerated()), id: \.offset) { _, check in
                Text(line(check)).font(Theme.jp(13)).opacity(0.85).fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onAsk) {
                Text("いまどうする？").font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44).background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        let ahead = preparation.ahead(of: day)
        if !ahead.isEmpty { label("これから") }
        ForEach(ahead, id: \.id) { pendingCard($0) }
    }

    /// 「15:00から　ホテル（例）京都駅前にチェックイン」: the time first, then the name.
    private func line(_ check: Preparation.Check) -> String {
        switch check.kind {
        case .opens: "\(DaySchedule.clock(check.minutes ?? 0))から　\(check.title)にチェックイン"
        case .fixed:
            "\(DaySchedule.clock(check.minutes ?? 0))　\(check.title)（"
                + (check.isBooked.map { $0 ? "予約：済み・" : "予約：まだ・" } ?? "") + "時刻は動かしません）"
        case .luggage: "？　\(check.title)"
        }
    }

    // MARK: - Cards

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("宿を足すと、ここに予約が並びます").font(Theme.jp(16, .bold)).foregroundStyle(Theme.ink)
            Text("ほかの予定も、予定の詳細で「予約が要る」にするとここに出ます。")
                .font(Theme.jp(13)).foregroundStyle(Theme.secondary)
            Button(action: onAddPlans) {
                Text("予定を足す").font(Theme.jp(15, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 20).frame(minHeight: 44).background(Capsule().fill(Theme.ink))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.fill))
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.jp(13, .bold)).foregroundStyle(Theme.secondary)
    }

    private func blackCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24).fill(Theme.ink))
    }

    /// The thing to do now: 「宿を予約する」 and 「予約完了にする」. The card opens the plan's detail.
    private func bookCard(_ item: ItineraryItem, small: String, rows: [String]) -> some View {
        blackCard {
            Button { onOpen(item) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(small).font(Theme.jp(12, .medium)).opacity(0.7).fixedSize(horizontal: false, vertical: true)
                    Text(Preparation.bookTitle(of: item)).font(Theme.jp(22, .bold))
                    ForEach(rows, id: \.self) { Text($0).font(Theme.jp(13)).opacity(0.85) }
                    if item.kind == .stay, let opens = item.notBeforeMinutes {
                        Text("\(DaySchedule.clock(opens))からチェックイン。予約したら「予約完了にする」")
                            .font(Theme.jp(13)).opacity(0.85).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { onBook(item) } label: {
                Text("予約完了にする").font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44).background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
        }
    }

    private func pendingCard(_ item: ItineraryItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { onOpen(item) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Preparation.context(of: item, days: days)).font(Theme.jp(12, .medium))
                        .foregroundStyle(Theme.secondary)
                    Text(item.title).font(Theme.jp(18, .bold)).foregroundStyle(Theme.ink).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack {
                Text("予約：まだ").font(Theme.jp(13, .medium)).foregroundStyle(Theme.ink)
                Spacer()
                Button { onBook(item) } label: {
                    Text("予約完了にする").font(Theme.jp(14, .bold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line))
    }

    private func bookedRow(_ item: ItineraryItem) -> some View {
        Button { onOpen(item) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Preparation.context(of: item, days: days)).font(Theme.jp(12, .medium))
                        .foregroundStyle(Theme.secondary)
                    Text(item.title).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink).lineLimit(2)
                }
                Spacer()
                Text("予約：済み ✓").font(Theme.jp(13, .medium)).foregroundStyle(Theme.ink)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.fill))
        }
        .buttonStyle(.plain)
    }
}
