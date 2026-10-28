import SwiftUI

extension AddStaySheet {
    /// 「どこに泊まる？」 (Figma 15-7): the four kinds, each with what it asks for.
    var kindList: some View {
        VStack(spacing: 10) {
            ForEach(StayKind.allCases) { option in
                Button {
                    withAnimation(.snappy) { kind = option }
                    isTyping = option != .later
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.label).font(Theme.jp(16, .bold)).foregroundStyle(Theme.ink)
                            Text(option.detail).font(Theme.jp(12, .medium)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.faint)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The kind chosen, shrunk to one line (as in trip creation); tapping it chooses again.
    func chosenKind(_ chosen: StayKind) -> some View {
        Button {
            withAnimation(.snappy) {
                kind = nil
                place = nil
                query = ""
            }
        } label: {
            collapsedRow("どこに泊まる？", value: chosen.label)
        }
        .buttonStyle(.plain)
    }

    func collapsedRow(_ label: String, value: String, chevron: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(label).font(Theme.jp(13)).foregroundStyle(Theme.secondary)
            Spacer()
            Text(value).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink)
            if chevron {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.fill))
        .contentShape(Rectangle())
    }

    /// A name of one's own for an Airbnb・民泊 or a friend's house.
    func nameField(_ chosen: StayKind) -> some View {
        TextField(chosen == .friend ? "名前（例：さきの家）" : "名前（なくてもいい）", text: $name)
            .font(Theme.jp(15, .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 1))
    }

    /// The place chosen with 「変える」, or the search while there is none.
    @ViewBuilder
    func placeSection(_ chosen: StayKind) -> some View {
        if let place {
            HStack(spacing: 12) {
                Image(systemName: chosen == .hotel ? "bed.double" : "mappin")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.fill))
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.title).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(place.town ?? place.detail).font(Theme.jp(12)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("変える") {
                    withAnimation(.snappy) { self.place = nil }
                    isTyping = true
                }
                .font(Theme.jp(13, .medium))
                .foregroundStyle(Theme.ink)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.ink, lineWidth: 1.5))
        } else {
            searchField(chosen == .hotel ? "ホテルの名前" : "住所")
            ForEach(search.results) { result in
                Button { choose(result) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: result.kind.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.fill))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.title).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                            Text(result.detail).font(Theme.jp(12, .medium)).foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
                    .opacity(resolvingID == result.id ? 0.5 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func searchField(_ prompt: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            TextField(prompt, text: $query)
                .font(Theme.jp(15, .medium))
                .foregroundStyle(Theme.ink)
                .focused($isTyping)
                .submitLabel(.done)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.fill))
    }

    /// 「泊まり始める日 ▾」, 「何泊？ − 2 泊 ＋」 with the dates, the note and 「追加」 (Figma 15-8).
    func nightsSection(_ chosen: StayKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            startDay
            Text("何泊？").font(Theme.jp(12)).foregroundStyle(Theme.secondary)
            HStack(spacing: 16) {
                stepButton("minus", enabled: nights > 1) { nights -= 1 }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(nights)").font(Theme.latin(28, .bold)).foregroundStyle(Theme.ink)
                    Text("泊").font(Theme.jp(13)).foregroundStyle(Theme.ink)
                }
                stepButton("plus", enabled: maxNights.map { nights < $0 } ?? true) { nights += 1 }
                Spacer(minLength: 4)
                if let range = nightsRange {
                    Text(range).font(Theme.jp(13, .medium)).foregroundStyle(Theme.ink)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
            Text(note(chosen)).font(Theme.jp(12)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { add() } label: {
                Text("追加")
                    .font(Theme.jp(17, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(Theme.ink))
            }
            .buttonStyle(.plain)
        }
    }

    private func note(_ chosen: StayKind) -> String {
        switch chosen {
        case .friend: "予約の印は付きません（準備タブにも出ません）。着く時刻・出る時刻は、追加したあと詳細で入れられます"
        case .later: "旅程には「宿」とだけ置き、準備タブに「宿を決める」と出します"
        case .hotel, .rental: "チェックイン・チェックアウトの時刻と予約は、追加したあと詳細で入れます"
        }
    }

    private var startDay: some View {
        Menu {
            Button("未定") { day = nil }
            ForEach(days.days, id: \.number) { item in
                Button(days.tabLabel(item)) { day = item.number }
            }
        } label: {
            collapsedRow("泊まり始める日", value: startDayName, chevron: !days.days.isEmpty)
        }
        .disabled(days.days.isEmpty)
    }

    private var startDayName: String {
        guard let day, let item = days.days.first(where: { $0.number == day }) else { return "未定" }
        return days.tabLabel(item)
    }

    /// 「11/9（土）〜11/11（月）」: from the first night to the day the stay is left.
    private var nightsRange: String? {
        guard let start = days.date(of: day),
              let end = text.calendar.date(byAdding: .day, value: nights, to: start) else { return nil }
        return text.shortRange(start, end)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
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
}
