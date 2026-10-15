import SwiftUI

/// Temporary Home for one trip: name, destinations and dates only.
/// The real Plan Home (photo cover, next action) is the next Issue; this view is not it.
struct TripPlaceholderHomeView: View {
    let trip: Trip
    let onCreateAnother: () -> Void

    private var dateText: DateText { DateText(calendar: .current, holidays: .bundled) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("仮のHome")
                .font(Theme.jp(12, .medium))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.fill))

            Text(trip.name)
                .font(Theme.jp(30, .bold))
                .foregroundStyle(Theme.ink)

            VStack(alignment: .leading, spacing: 12) {
                row("行き先", trip.destinations.isEmpty ? "未定" : trip.destinations.map(\.name).joined(separator: "・"))
                row("日付", dateSummary)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))

            Spacer()

            Button(action: onCreateAnother) {
                Text("別の旅行を作る")
                    .font(Theme.jp(15, .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().strokeBorder(Theme.line))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.base.ignoresSafeArea())
    }

    /// Notion 02 §6-3: fixed → days until departure, days only → 「この旅は○日間」, undecided → 「いつ行くか 未定」.
    private var dateSummary: String {
        switch trip.dates {
        case .undecided:
            return "いつ行くか 未定"
        case .days(let count):
            return "この旅は\(count)日間"
        case .range(let start, let end):
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: start).day ?? 0
            let lead = days > 0 ? "あと\(days)日で出発" : (days == 0 ? "今日出発" : "旅行中・終了")
            return "\(dateText.range(start, end))　\(lead)"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Theme.jp(15)).foregroundStyle(Theme.secondary)
            Spacer(minLength: 12)
            Text(value).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
        }
    }
}
