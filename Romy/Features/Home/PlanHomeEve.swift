import SwiftUI

/// 「準備 ・ 予約 3つ中1つ済み ›」 under the next action (Notion 02 §6-3 採用 2026-10-28, Figma 29-01): the same count as
/// 準備; tapping it opens 準備.
struct PlanHomeSummaryRow: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(text).font(Theme.jp(14, .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 旅程のちょい見せ (Figma 29-01): each day with how many plans it has; tapping one opens that day of the itinerary.
struct PlanHomeDayGlance: View {
    let counts: [PlanHomeGlance.DayCount]
    let onOpenDay: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("旅程").font(Theme.jp(14, .bold)).foregroundStyle(Theme.ink)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(counts) { day in
                        Button { onOpenDay(day.day) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Circle().fill(Theme.dayColor(day.day)).frame(width: 7, height: 7)
                                    Text(day.label).font(Theme.latin(14, .bold)).foregroundStyle(Theme.ink)
                                }
                                Text("\(day.count)件").font(Theme.jp(12)).foregroundStyle(Theme.secondary)
                            }
                            .padding(14)
                            .frame(minWidth: 104, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(day.label)、予定\(day.count)件")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// 前日のHome (Notion 02 §6-3 採用 2026-10-28, Figma 29-02 / 29-03): the black card has tomorrow's first plan and
/// 「明日の準備 2 / 3」 with the booking still to make; below it the plans after the first. Without plans the card
/// says so and offers the itinerary; without anything to book there is no 「明日の準備」.
struct PlanHomeEve: View {
    let eve: PlanHomeGlance.Eve
    let preparation: Preparation
    let caption: String
    let onOpenPlan: (UUID) -> Void
    let onOpenDay: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            card
            if !eve.rest.isEmpty {
                Text("明日の流れ").font(Theme.jp(14, .bold)).foregroundStyle(Theme.ink)
                ForEach(eve.rest, id: \.id) { line in
                    Button { onOpenPlan(line.id) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(Theme.dayColor(1)).frame(width: 7, height: 7)
                            Text(line.text).font(Theme.jp(14, .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let first = eve.first {
                Text("明日の最初の予定 ・ \(caption)").font(Theme.jp(12, .medium)).opacity(0.7)
                Button { onOpenPlan(first.id) } label: {
                    Text(first.text).font(Theme.jp(22, .bold)).lineLimit(2).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            } else {
                Text("明日の予定はまだありません").font(Theme.jp(20, .bold))
            }
            if preparation.total > 0 {
                progress
            }
            button
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.ink))
    }

    /// 「━ ━ ・  明日の準備 2 / 3」
    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<preparation.total, id: \.self) { index in
                Capsule()
                    .fill(index < preparation.booked.count ? Color.white : Color.white.opacity(0.3))
                    .frame(width: index < preparation.booked.count ? 22 : 10, height: 6)
            }
            Text("  明日の準備 \(preparation.booked.count) / \(preparation.total)")
                .font(Theme.jp(12, .medium)).opacity(0.8)
        }
    }

    /// The booking still to make, 「明日の準備はOK」 when all are made, or 「旅程を見る」 without plans.
    @ViewBuilder
    private var button: some View {
        if eve.first == nil {
            whiteButton("旅程を見る") { onOpenDay(1) }
        } else if let next = preparation.pending.first {
            whiteButton(PlanHomeGlance.bookTitle(of: next)) { onOpenPlan(next.id) }
        } else if preparation.total > 0 {
            HStack {
                Text("明日の準備はOK").font(Theme.jp(15, .bold))
                Spacer()
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Capsule().fill(Color.white.opacity(0.85)))
            .accessibilityAddTraits(.isStaticText)
        }
    }

    private func whiteButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(Theme.jp(15, .bold)).lineLimit(1)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.ink))
            }
            .foregroundStyle(Theme.ink)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(minHeight: 48)
            .background(Capsule().fill(Color.white))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
