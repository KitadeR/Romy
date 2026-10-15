import SwiftData
import SwiftUI

/// 「＋ 行き先を追加」 on the map of a trip without a destination (Notion 02 §6-6, Figma 16-6).
/// The same search card as trip creation. A name the app gave is renamed after the destinations
/// (「新しい旅行」→「京都旅行」); a name the person typed is kept.
struct AddDestinationsSheet: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @Query private var trips: [Trip]
    @State private var model = TripCreationModel()
    @FocusState private var focusedField: TripCreationModel.Step?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("閉じる")
                Spacer()
            }
            .padding(.horizontal, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DestinationSearchCard(model: model, focusedField: $focusedField)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Theme.surface)
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .scrollDismissesKeyboard(.interactively)

            Button(action: decide) {
                Text("決める")
                    .font(Theme.jp(17, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(Theme.ink))
            }
            .buttonStyle(.plain)
            .opacity(model.destinations.isEmpty ? 0.3 : 1)
            .disabled(model.destinations.isEmpty)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(Theme.base.ignoresSafeArea())
        .onAppear {
            model.destinations = trip.destinations
            focusedField = .destinations
        }
    }

    private func decide() {
        trip.destinations = model.destinations
        if trip.isNameAuto {
            trip.name = TripNaming.autoName(
                destinations: model.destinations,
                dates: trip.dates,
                existingNames: trips.filter { $0.id != trip.id }.map(\.name),
                calendar: .current
            )
        }
        dismiss()
    }
}
