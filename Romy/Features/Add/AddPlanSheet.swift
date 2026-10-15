import MapKit
import SwiftData
import SwiftUI

/// 「行きたい所・予定を追加」 (Notion 02 §6-6 ＋ボタン ①, Figma 15-2 / 15-3).
/// Search a place, or add by name only. The day comes from where it was opened and can be changed with ▾.
/// The 「行きたい」 list in this sheet and the ♡ come with the 行きたい tab (Notion 05).
struct AddPlanSheet: View {
    let trip: Trip
    let onAdded: (ItineraryItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var day: Int?
    @State private var query = ""
    @State private var search = PlaceSearch()
    @FocusState private var isTyping: Bool

    private let text = DateText(calendar: .current, holidays: .bundled)
    private var days: ItineraryDays { ItineraryDays(dates: trip.dates, text: text) }
    private var typed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(trip: Trip, day: Int?, onAdded: @escaping (ItineraryItem) -> Void) {
        self.trip = trip
        self.onAdded = onAdded
        _day = State(initialValue: ItineraryDays.placement(of: day, dayCount: ItineraryDays.count(of: trip.dates)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("行きたい所・予定を追加").font(Theme.jp(22, .bold)).foregroundStyle(Theme.ink)
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
            dayPicker
            searchField
            ScrollView {
                VStack(spacing: 10) {
                    if !typed.isEmpty {
                        row(
                            icon: AnyView(Text("Aa").font(Theme.latin(15, .bold)).foregroundStyle(Theme.secondary)),
                            title: "「\(typed)」を名前だけで追加",
                            detail: "場所なしの予定（あとで場所を足せる）"
                        ) { addByName() }
                        ForEach(search.results) { result in
                            row(
                                icon: AnyView(Image(systemName: result.kind.symbol)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.secondary)),
                                title: result.title,
                                detail: result.detail
                            ) { add(result) }
                        }
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
        .onAppear { isTyping = true }
    }

    // MARK: - Parts

    private var dayPicker: some View {
        HStack(spacing: 8) {
            Text("入れる日").font(Theme.jp(12, .medium)).foregroundStyle(Theme.secondary)
            if days.days.isEmpty {
                dayChip
            } else {
                Menu {
                    Button("未定") { day = nil }
                    ForEach(days.days, id: \.number) { item in
                        Button(days.tabLabel(item)) { day = item.number }
                    }
                } label: {
                    dayChip
                }
            }
        }
    }

    private var dayChip: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.dayColor(day)).frame(width: 6, height: 6)
            Text(dayName).font(Theme.jp(13, .bold)).foregroundStyle(Theme.ink)
            if !days.days.isEmpty {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(Theme.fill))
    }

    private var dayName: String {
        guard let day, let item = days.days.first(where: { $0.number == day }) else { return "未定" }
        return days.tabLabel(item)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            TextField("場所や予定の名前", text: $query)
                .font(Theme.jp(15, .medium))
                .foregroundStyle(Theme.ink)
                .focused($isTyping)
                .submitLabel(.done)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("消す")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.fill))
    }

    private func row(icon: AnyView, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.fill))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(detail).font(Theme.jp(12, .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.ink))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)、\(detail)、追加")
    }

    // MARK: - Adding

    private func addByName() {
        insert(ItineraryItem(title: typed, day: day, order: trip.nextOrder(on: day), kind: .nameOnly))
    }

    private func add(_ result: PlaceSearch.Result) {
        let coordinate = result.item.location.coordinate
        let item = ItineraryItem(
            title: result.title,
            day: day,
            order: trip.nextOrder(on: day),
            kind: result.kind,
            category: result.category,
            area: result.town,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            placeID: result.item.identifier?.rawValue
        )
        insert(item)
        // The ward is looked up once, after saving, so adding is not kept waiting.
        Task {
            let ward = await PlaceSearch.lookUpWard(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let ward, !item.isDeleted, item.modelContext != nil else { return }
            item.area = ward
            try? item.modelContext?.save()
        }
    }

    private func insert(_ item: ItineraryItem) {
        modelContext.insert(item)
        item.trip = trip
        try? modelContext.save()
        onAdded(item)
        dismiss()
    }
}
