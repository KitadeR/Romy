import SwiftUI

/// 宿の決まりのカード in a stay's detail (Notion 02 §6-5 採用 2026-10-28, Figma 15-10): when check-in opens (and its
/// last time) large, then the check-out and the nights with the kind. 「変える」 opens `StayRulesSheet`.
struct StayRulesCard: View {
    let item: ItineraryItem
    let days: ItineraryDays

    @State private var isEditing = false

    var body: some View {
        Button { isEditing = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("チェックインできる時間").font(Theme.jp(12, .bold)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text("変える ›").font(Theme.jp(13, .medium)).foregroundStyle(Theme.ink)
                }
                Text(Self.opening(of: item) ?? "時刻を入れる")
                    .font(item.notBeforeMinutes == nil ? Theme.jp(15, .bold) : Theme.latin(20, .bold))
                    .foregroundStyle(item.notBeforeMinutes == nil ? Theme.secondary : Theme.ink)
                if let leaving = checkOut {
                    Text(leaving).font(Theme.jp(13, .medium)).foregroundStyle(Theme.ink)
                }
                Text("\(item.nights)泊 ・ \(item.stayKind.label)").font(Theme.jp(12)).foregroundStyle(Theme.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isEditing) {
            StayRulesSheet(item: item, dayCount: days.days.count)
                .presentationDetents([.large])
        }
    }

    /// 「15:00〜22:00」, or 「15:00から」 without a last check-in.
    static func opening(of item: ItineraryItem) -> String? {
        guard let from = item.notBeforeMinutes else { return nil }
        guard let last = item.lastCheckInMinutes else { return "\(DaySchedule.clock(from))から" }
        return "\(DaySchedule.clock(from))〜\(DaySchedule.clock(last))"
    }

    /// 「チェックアウト 11/11（月）11:00まで」, with the day when the trip has no dates.
    private var checkOut: String? {
        guard let minutes = item.checkOutMinutes else { return nil }
        let calendar = days.text.calendar
        let leavingDate = days.date(of: item.day).flatMap { calendar.date(byAdding: .day, value: item.nights, to: $0) }
        let day = leavingDate.map { days.text.day($0) } ?? item.leavingDay.map { "\($0)日目" }
        return ["チェックアウト", day, "\(DaySchedule.clock(minutes))まで"].compactMap { $0 }.joined(separator: "  ")
    }
}
