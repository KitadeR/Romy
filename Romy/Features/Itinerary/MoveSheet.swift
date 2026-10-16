import SwiftUI

/// 「どの日に入れる？」 (Notion 02 §6-3 予定を動かす, Figma 17-5): the days with how many plans each has, 未定,
/// and one black button. For now a tap on a plan opens this; the plan's detail sheet will hold it later (Notion 05).
struct MoveSheet: View {
    let trip: Trip
    let item: ItineraryItem

    @Environment(\.dismiss) private var dismiss
    @State private var choice: Int?

    private let text = DateText(calendar: .current, holidays: .bundled)
    private var days: ItineraryDays { ItineraryDays(dates: trip.dates, text: text) }

    init(trip: Trip, item: ItineraryItem) {
        self.trip = trip
        self.item = item
        let dayCount = ItineraryDays.count(of: trip.dates)
        _choice = State(initialValue: ItineraryDays.placement(of: item.day, dayCount: dayCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("「\(item.title)」をどの日に入れる？")
                .font(Theme.jp(20, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 28)

            ForEach(days.days, id: \.number) { day in
                row(
                    title: days.tabLabel(day), color: Theme.dayColor(day.number),
                    count: trip.items(on: day.number).count, isSelected: choice == day.number
                ) { choice = day.number }
            }

            Text("または")
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

            Button {
                trip.move(item, toDay: choice)
                dismiss()
            } label: {
                Text(choice.map { "\($0)日目に入れる" } ?? "未定に戻す")
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

    private func row(
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
