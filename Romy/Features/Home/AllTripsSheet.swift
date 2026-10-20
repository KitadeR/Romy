import SwiftData
import SwiftUI

/// 「すべての旅行」 from the trip name ▾ (Notion 02 §6-3): switch trips, make a new one, and with a swipe to the
/// side rename (編集) or delete (削除) a trip. A trip's name can be changed after it is made (Notion 02 §1, 2026-10-07).
/// Duplicating a trip comes later (Notion 05).
struct AllTripsSheet: View {
    let current: Trip
    /// Called before the sheet closes; the caller opens trip creation after it has closed.
    let onCreateTrip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.lastOpenedAt, order: .reverse) private var trips: [Trip]
    @State private var renaming: Trip?
    @State private var draft = ""
    @State private var deleting: Trip?

    private let text = DateText(calendar: .current, holidays: .bundled)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("すべての旅行")
                .font(Theme.jp(20, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 24)
                .padding(.horizontal, 20)

            List {
                ForEach(trips) { trip in
                    Button { open(trip) } label: { row(trip) }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { startRenaming(trip) } label: { Label("編集", systemImage: "pencil") }
                                .tint(Theme.ink)
                            Button(role: .destructive) { deleting = trip } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

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
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(Theme.base.ignoresSafeArea())
        .alert("旅行名を変える", isPresented: isRenaming) {
            TextField(autoNamePlaceholder, text: $draft)
            Button("保存", action: saveName)
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("空にすると、自動の名前に戻ります。")
        }
        .alert(deleteTitle, isPresented: isDeleting) {
            Button("削除", role: .destructive) { if let deleting { delete(deleting) } }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("予定と「行きたい」も一緒に消え、元に戻せません。")
        }
    }

    private func row(_ trip: Trip) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name).font(Theme.jp(16, .bold)).foregroundStyle(Theme.ink)
                Text(TripCountdown(dates: trip.dates, today: AppClock.now, text: text).caption)
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

    // MARK: - Rename

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    /// The name that is given when the field is left blank, shown faintly in the field (Notion 02 §1).
    private var autoNamePlaceholder: String {
        guard let renaming else { return "" }
        return TripNaming.autoName(
            destinations: renaming.destinations, dates: renaming.dates,
            existingNames: trips.filter { $0.id != renaming.id }.map(\.name), calendar: .current
        )
    }

    private func startRenaming(_ trip: Trip) {
        // The name the app gave is shown as the placeholder only, so a blank field means 「自動のままにする」.
        draft = trip.isNameAuto ? "" : trip.name
        renaming = trip
    }

    private func saveName() {
        guard let trip = renaming else { return }
        let edited = TripNaming.edited(
            draft, destinations: trip.destinations, dates: trip.dates,
            existingNames: trips.filter { $0.id != trip.id }.map(\.name), calendar: .current
        )
        trip.name = edited.name
        trip.isNameAuto = edited.isAuto
        try? modelContext.save()
    }

    // MARK: - Delete

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var deleteTitle: String { "「\(deleting?.name ?? "")」を削除しますか？" }

    /// Deletes a trip. When it is the one open, another trip is opened first and the sheet closes, and the trip is
    /// deleted only after the screen has moved off it; without another trip, the first Home comes back.
    private func delete(_ trip: Trip) {
        guard trip.id == current.id else {
            modelContext.delete(trip)
            try? modelContext.save()
            return
        }
        trips.first { $0.id != trip.id }?.lastOpenedAt = .now
        dismiss()
        let context = modelContext
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            context.delete(trip)
            try? context.save()
        }
    }
}
