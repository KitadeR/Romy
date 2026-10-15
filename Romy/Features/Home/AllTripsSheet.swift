import SwiftData
import SwiftUI

/// 「すべての旅行」 from the trip name ▾ (Notion 02 §6-3): switch trips or make a new one.
/// Duplicate and delete come later (Notion 05).
struct AllTripsSheet: View {
    let current: Trip
    /// Called before the sheet closes; the caller opens trip creation after it has closed.
    let onCreateTrip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Trip.lastOpenedAt, order: .reverse) private var trips: [Trip]

    private let text = DateText(calendar: .current, holidays: .bundled)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("すべての旅行")
                .font(Theme.jp(20, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 24)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(trips) { trip in
                        Button { open(trip) } label: { row(trip) }
                            .buttonStyle(.plain)
                    }
                }
            }

            Button {
                onCreateTrip()
                dismiss()
            } label: {
                Text("新しい旅行を作る")
                    .font(Theme.jp(17, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(Theme.ink))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .background(Theme.base.ignoresSafeArea())
    }

    private func row(_ trip: Trip) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name).font(Theme.jp(16, .bold)).foregroundStyle(Theme.ink)
                Text(TripCountdown(dates: trip.dates, today: .now, text: text).caption)
                    .font(Theme.jp(12, .medium))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            if trip.id == current.id {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
        .accessibilityAddTraits(trip.id == current.id ? .isSelected : [])
    }

    /// The app opens the trip opened last, so switching is just marking it opened now.
    private func open(_ trip: Trip) {
        trip.lastOpenedAt = .now
        dismiss()
    }
}
