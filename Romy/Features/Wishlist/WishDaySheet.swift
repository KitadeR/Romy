import SwiftData
import SwiftUI

/// 「どの日に入れる？」 for a saved place (Notion 02 §6-6): the days and 未定, then one black button. The wish stays
/// in 「行きたい」 afterwards, marked as added.
struct WishDaySheet: View {
    let trip: Trip
    let wish: WishPlace
    let onAdded: (ItineraryItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var choice: Int?

    private let text = DateText(calendar: .current, holidays: .bundled)
    private var days: ItineraryDays { ItineraryDays(dates: trip.dates, text: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("「\(wish.title)」をどの日に入れる？")
                .font(Theme.jp(20, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 28)
            ForEach(days.days, id: \.number) { day in
                choiceRow(
                    title: days.tabLabel(day), color: Theme.dayColor(day.number),
                    count: trip.items(on: day.number).count, isSelected: choice == day.number
                ) { choice = day.number }
            }
            Text(days.days.isEmpty ? "日付が決まるまでは未定に入ります" : "または")
                .font(Theme.jp(12, .medium))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 4)
            Button { choice = nil } label: {
                Text("未定（日はあとで決める）")
                    .font(Theme.jp(14, .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.fill))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.ink, lineWidth: choice == nil ? 2 : 0)
                    )
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button(action: add) {
                Text(choice.map { "\($0)日目に入れる" } ?? "未定に入れる")
                    .font(Theme.jp(17, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(Theme.ink))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .background(Theme.surface.ignoresSafeArea())
    }

    private func add() {
        let item = trip.addPlan(from: wish, toDay: choice)
        modelContext.insert(item)
        item.trip = trip
        try? modelContext.save()
        onAdded(item)
        dismiss()
    }

    private func choiceRow(
        title: String, color: Color, count: Int, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(title).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(count)件").font(Theme.jp(12, .medium)).foregroundStyle(Theme.secondary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Theme.ink : Theme.line, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
