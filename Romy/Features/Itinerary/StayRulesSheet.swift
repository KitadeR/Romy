import MapKit
import SwiftData
import SwiftUI

/// 宿の決まりを入れる (Notion 02 §6-5 採用 2026-10-28, Figma 15-11): the kind, the nights, and the times from the
/// booking — check-in opens, the last check-in (optional) and check-out. Tapping a time opens the wheel under it.
/// Nothing is saved until 「保存」. A stay decided later that becomes a hotel and so on is given its place here, with
/// the same search as 「宿を追加」.
struct StayRulesSheet: View {
    enum Field: Hashable { case opens, last, checkOut }

    let item: ItineraryItem
    let dayCount: Int

    @Environment(\.dismiss) private var dismiss
    @State private var kind: StayKind
    @State private var nights: Int
    @State private var times: [Field: Int]
    @State private var editing: Field?
    @State private var place: PlaceSearch.Result?
    @State private var isFindingPlace = false

    /// Where the wheel starts for a time not put in yet (宿の調査 2026-10-28: 15:00から・22:00まで・11:00まで).
    private static let firstGuess: [Field: Int] = [.opens: 15 * 60, .last: 22 * 60, .checkOut: 11 * 60]

    init(item: ItineraryItem, dayCount: Int) {
        self.item = item
        self.dayCount = dayCount
        _kind = State(initialValue: item.stayKind)
        _nights = State(initialValue: item.nights)
        var times: [Field: Int] = [:]
        times[.opens] = item.notBeforeMinutes
        times[.last] = item.lastCheckInMinutes
        times[.checkOut] = item.checkOutMinutes
        _times = State(initialValue: times)
    }

    private var maxNights: Int? { StayNights.maxNights(from: item.day, dayCount: dayCount) }
    private var hasPlace: Bool { place != nil || item.latitude != nil }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(item.title).font(Theme.jp(20, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
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
            .padding(.top, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    kindRow
                    if kind != .later, !hasPlace { placeRow }
                    Text("何泊？").font(Theme.jp(12)).foregroundStyle(Theme.secondary).padding(.top, 4)
                    nightsRow
                    Text("宿の決まり（予約の確認メールに書いてある時刻）")
                        .font(Theme.jp(12)).foregroundStyle(Theme.secondary).padding(.top, 6)
                    timeRow(.opens, label: "チェックインできる時間", suffix: "から")
                    timeRow(.last, label: "最終チェックイン（なくてもいい）", suffix: "まで")
                    timeRow(.checkOut, label: "チェックアウト", suffix: "まで")
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            Button { save() } label: {
                Text("保存")
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
        .sheet(isPresented: $isFindingPlace) {
            StayPlacePicker(kind: kind, trip: item.trip) { place = $0 }
                .presentationDetents([.large])
        }
    }

    private var kindRow: some View {
        Menu {
            ForEach(StayKind.allCases) { option in
                Button(option.label) { kind = option }
            }
        } label: {
            row("宿の種類", value: "\(kind.label) ›")
        }
    }

    /// A stay decided later gets its place once it is a hotel, an Airbnb・民泊 or a friend's house.
    private var placeRow: some View {
        Button { isFindingPlace = true } label: {
            row("場所", value: place?.title ?? "探す ›")
        }
        .buttonStyle(.plain)
    }

    private var nightsRow: some View {
        HStack(spacing: 16) {
            step("minus", enabled: nights > 1) { nights -= 1 }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(nights)").font(Theme.latin(28, .bold)).foregroundStyle(Theme.ink)
                Text("泊").font(Theme.jp(13)).foregroundStyle(Theme.ink)
            }
            step("plus", enabled: maxNights.map { nights < $0 } ?? true) { nights += 1 }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func timeRow(_ field: Field, label: String, suffix: String) -> some View {
        let isOpen = editing == field
        Button {
            withAnimation(.snappy) {
                editing = isOpen ? nil : field
                if !isOpen, times[field] == nil { times[field] = Self.firstGuess[field] }
            }
        } label: {
            row(label, value: times[field].map { "\(DaySchedule.clock($0))\(suffix)" } ?? "入れる", isOpen: isOpen)
        }
        .buttonStyle(.plain)
        if isOpen {
            DatePicker("", selection: wheel(field), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "en_GB"))
                .frame(maxWidth: .infinity)
            Button("時刻を外す") {
                withAnimation(.snappy) {
                    times[field] = nil
                    editing = nil
                }
            }
            .font(Theme.jp(14, .bold))
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity)
        }
    }

    private func row(_ label: String, value: String, isOpen: Bool = false) -> some View {
        HStack {
            Text(label).font(Theme.jp(13)).foregroundStyle(Theme.secondary)
            Spacer()
            Text(value).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 14).fill(isOpen ? Color.white : Theme.fill))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isOpen ? Theme.ink : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
    }

    private func step(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.fill))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(symbol == "plus" ? "1泊ふやす" : "1泊へらす")
    }

    /// The wheel works in dates; the time is kept as minutes after midnight.
    private func wheel(_ field: Field) -> Binding<Date> {
        Binding {
            let minutes = times[field] ?? Self.firstGuess[field] ?? 0
            return Calendar.current.date(
                bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: .now
            ) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            times[field] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private func save() {
        item.stayKind = kind
        item.nights = nights
        item.notBeforeMinutes = times[.opens]
        item.lastCheckInMinutes = times[.last]
        item.checkOutMinutes = times[.checkOut]
        if let place, let found = place.item {
            if item.title == "宿" { item.title = place.title }
            let coordinate = found.location.coordinate
            item.latitude = coordinate.latitude
            item.longitude = coordinate.longitude
            item.placeID = found.identifier?.rawValue
            item.area = place.town
        }
        try? item.modelContext?.save()
        dismiss()
    }
}
