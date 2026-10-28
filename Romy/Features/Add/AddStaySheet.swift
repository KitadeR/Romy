import MapKit
import SwiftData
import SwiftUI

/// 「宿を追加」 (Notion 02 §6-5 採用 2026-10-28, Figma 15-7・15-8・15-8b〜d): 「どこに泊まる？」 first, then only what
/// that kind needs — a hotel is searched by name, an Airbnb・民泊 and a friend's house by address with a name of
/// one's own, a stay decided later has no place. The first night comes from where the sheet was opened and can be
/// changed with ▾; the nights go up to the end of the trip. Times and the booking are put in the stay's detail.
struct AddStaySheet: View {
    let trip: Trip
    let onAdded: (ItineraryItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State var kind: StayKind?
    @State var day: Int?
    @State var nights = 1
    @State var query = ""
    @State var name = ""
    @State var search = PlaceSearch()
    /// The place chosen, once Apple's search has found where it is.
    @State var place: PlaceSearch.Result?
    /// The suggestion being looked up after it was tapped.
    @State var resolvingID: String?
    @FocusState var isTyping: Bool

    let text = DateText(calendar: .current, holidays: .bundled)
    var days: ItineraryDays { ItineraryDays(dates: trip.dates, text: text) }
    var maxNights: Int? { StayNights.maxNights(from: day, dayCount: ItineraryDays.count(of: trip.dates)) }

    init(trip: Trip, day: Int?, onAdded: @escaping (ItineraryItem) -> Void) {
        self.trip = trip
        self.onAdded = onAdded
        _day = State(initialValue: ItineraryDays.placement(of: day, dayCount: ItineraryDays.count(of: trip.dates)))
    }

    /// Everything the kind asks for is in: a place, except for a stay decided later.
    private var isReady: Bool {
        guard let kind else { return false }
        return kind == .later || place != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let kind {
                        chosenKind(kind)
                        if kind != .hotel, kind != .later { nameField(kind) }
                        if kind != .later { placeSection(kind) }
                        if isReady { nightsSection(kind) }
                    } else {
                        kindList
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .background(Theme.surface.ignoresSafeArea())
        .task { await search.prepare(for: trip.destinations) }
        .onChange(of: query) { _, newValue in search.update(query: newValue) }
        .onChange(of: day) { _, _ in
            if let maxNights { nights = min(nights, maxNights) }
        }
    }

    private var header: some View {
        HStack {
            Text(kind == nil ? "どこに泊まる？" : "宿を追加").font(Theme.jp(22, .bold)).foregroundStyle(Theme.ink)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.fill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
    }

    // MARK: - Adding

    /// The name on the itinerary: the hotel's, or the name typed (the place's when none is), or 「宿」.
    private var title: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .later, nil: return "宿"
        case .hotel: return place?.title ?? "宿"
        case .rental, .friend: return typed.isEmpty ? (place?.title ?? "宿") : typed
        }
    }

    func add() {
        guard let kind else { return }
        let coordinate = place?.item?.location.coordinate
        let item = ItineraryItem(
            title: title,
            day: day,
            order: trip.nextOrder(on: day),
            kind: .stay,
            category: kind == .hotel ? place?.category : nil,
            area: place?.town,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            placeID: place?.item?.identifier?.rawValue
        )
        item.stayKind = kind
        item.nights = nights
        modelContext.insert(item)
        item.trip = trip
        try? modelContext.save()
        if let coordinate {
            // The ward is looked up once, after saving, so adding is not kept waiting.
            Task {
                let ward = await PlaceSearch.lookUpWard(latitude: coordinate.latitude, longitude: coordinate.longitude)
                guard let ward, !item.isDeleted, item.modelContext != nil else { return }
                item.area = ward
                try? item.modelContext?.save()
            }
        }
        onAdded(item)
        dismiss()
    }

    /// A suggestion has no place yet, so it is looked up first.
    func choose(_ result: PlaceSearch.Result) {
        guard resolvingID == nil else { return }
        guard result.item == nil else {
            place = result
            isTyping = false
            return
        }
        resolvingID = result.id
        Task {
            let resolved = await PlaceSearch.resolve(result)
            resolvingID = nil
            if let resolved {
                place = resolved
                isTyping = false
            }
        }
    }
}
