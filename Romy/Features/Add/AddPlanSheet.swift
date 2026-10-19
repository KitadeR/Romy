import MapKit
import SwiftData
import SwiftUI

/// 「行きたい所・予定を追加」 (Notion 02 §6-6 ＋ボタン ①, Figma 15-2 / 15-3).
/// Search a place, or add by name only. The day comes from where it was opened and can be changed with ▾.
/// Each result also has a ♥ that saves the place in 「行きたい」 (Notion 02 §6-6); opened from 行きたい the sheet only
/// saves places: no day, no name-only plans.
struct AddPlanSheet: View {
    let trip: Trip
    let onAdded: (ItineraryItem) -> Void
    /// Opened from the 行きたい tab: results are saved with ♥ instead of being added to a day.
    let savesWishes: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var day: Int?
    @State private var query = ""
    @State private var search = PlaceSearch()
    /// The suggestion being looked up after it was tapped (it needs its place from Apple's search).
    @State private var resolvingID: String?
    @FocusState private var isTyping: Bool

    private let text = DateText(calendar: .current, holidays: .bundled)
    private var days: ItineraryDays { ItineraryDays(dates: trip.dates, text: text) }
    private var typed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(trip: Trip, day: Int?, onAdded: @escaping (ItineraryItem) -> Void) {
        self.trip = trip
        self.onAdded = onAdded
        savesWishes = false
        _day = State(initialValue: ItineraryDays.placement(of: day, dayCount: ItineraryDays.count(of: trip.dates)))
    }

    /// The 行きたい tab's search: places only, saved with ♥.
    init(trip: Trip) {
        self.trip = trip
        onAdded = { _ in }
        savesWishes = true
        _day = State(initialValue: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(savesWishes ? "行きたい所を探す" : "行きたい所・予定を追加").font(Theme.jp(22, .bold)).foregroundStyle(Theme.ink)
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
            if !savesWishes { dayPicker }
            searchField
            ScrollView {
                VStack(spacing: 10) {
                    if !typed.isEmpty {
                        if !savesWishes {
                            row(
                                icon: AnyView(Text("Aa").font(Theme.latin(15, .bold)).foregroundStyle(Theme.secondary)),
                                title: "「\(typed)」を名前だけで追加",
                                detail: "場所なしの予定（あとで場所を足せる）"
                            ) { addByName() }
                        }
                        ForEach(search.results) { result in
                            row(
                                icon: AnyView(Image(systemName: result.kind.symbol)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.secondary)),
                                title: result.title,
                                detail: result.detail,
                                isBusy: resolvingID == result.id,
                                heart: isSaved(result),
                                onHeart: { toggleWish(result) },
                                action: { savesWishes ? toggleWish(result) : add(result) }
                            )
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

    private func row(
        icon: AnyView, title: String, detail: String, isBusy: Bool = false,
        heart: Bool? = nil, onHeart: @escaping () -> Void = {}, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            rowButton(icon: icon, title: title, detail: detail, showsPlus: !savesWishes, action: action)
            if let heart {
                Button(action: onHeart) {
                    Image(systemName: heart ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(heart ? Theme.ink : Theme.secondary)
                        .frame(width: 40, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(heart ? "\(title)を行きたいから外す" : "\(title)を行きたいに保存")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
        .opacity(isBusy ? 0.5 : 1)
    }

    private func rowButton(
        icon: AnyView, title: String, detail: String, showsPlus: Bool, action: @escaping () -> Void
    ) -> some View {
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
                if showsPlus {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.ink))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsPlus ? "\(title)、\(detail)、追加" : "\(title)、\(detail)")
    }

    // MARK: - Adding

    private func addByName(_ title: String? = nil) {
        insert(ItineraryItem(title: title ?? typed, day: day, order: trip.nextOrder(on: day), kind: .nameOnly))
    }

    /// A suggestion has no place yet, so it is looked up first; if that fails it is added by name.
    private func add(_ result: PlaceSearch.Result) {
        guard resolvingID == nil else { return }
        guard result.item == nil else {
            addPlace(result)
            return
        }
        resolvingID = result.id
        Task {
            let resolved = await PlaceSearch.resolve(result)
            resolvingID = nil
            if let resolved {
                addPlace(resolved)
            } else {
                addByName(result.title)
            }
        }
    }

    private func addPlace(_ result: PlaceSearch.Result) {
        guard let place = result.item else { return }
        let coordinate = place.location.coordinate
        let item = ItineraryItem(
            title: result.title,
            day: day,
            order: trip.nextOrder(on: day),
            kind: result.kind,
            category: result.category,
            area: result.town,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            placeID: place.identifier?.rawValue
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

extension AddPlanSheet {
    // MARK: - Saving with ♥

    /// The saved place that is this result: the same Apple place, or (before it is looked up) the same name.
    private func savedWish(for result: PlaceSearch.Result) -> WishPlace? {
        trip.wishes.first { wish in
            if let id = result.item?.identifier?.rawValue, let placeID = wish.placeID { return id == placeID }
            return wish.title == result.title
        }
    }

    private func isSaved(_ result: PlaceSearch.Result) -> Bool { savedWish(for: result) != nil }

    /// ♥ saves the place in 「行きたい」, or takes it out when it is already there. A suggestion is looked up first.
    private func toggleWish(_ result: PlaceSearch.Result) {
        if let wish = savedWish(for: result) {
            modelContext.delete(wish)
            try? modelContext.save()
            return
        }
        guard resolvingID == nil else { return }
        guard result.item == nil else {
            saveWish(result)
            return
        }
        resolvingID = result.id
        Task {
            let resolved = await PlaceSearch.resolve(result)
            resolvingID = nil
            if let resolved { saveWish(resolved) }
        }
    }

    private func saveWish(_ result: PlaceSearch.Result) {
        guard let place = result.item else { return }
        let coordinate = place.location.coordinate
        let wish = WishPlace(
            title: result.title, kind: result.kind, category: result.category, area: result.town,
            latitude: coordinate.latitude, longitude: coordinate.longitude, placeID: place.identifier?.rawValue
        )
        modelContext.insert(wish)
        wish.trip = trip
        try? modelContext.save()
        Task {
            let ward = await PlaceSearch.lookUpWard(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let ward, !wish.isDeleted, wish.modelContext != nil else { return }
            wish.area = ward
            try? wish.modelContext?.save()
        }
    }
}
