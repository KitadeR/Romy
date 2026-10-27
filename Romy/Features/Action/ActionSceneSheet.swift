import SwiftUI

/// Figma 25, third version: one real map, compact ways, and the selected way's summary.
struct ActionSceneSheet: View {
    @State private var model: ActionSceneModel
    @Environment(LocationProvider.self) private var location
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editStates = false
    @State private var fromPlan = false
    @State private var revision = 0
    @State private var previewing = false
    @State private var problem: SceneApply.Problem?
    /// Puts the confirmed way into the itinerary; returns why it could not, or nil once it is in.
    let onApply: (SceneApply) -> SceneApply.Problem?

    init(request: SceneRequest, onApply: @escaping (SceneApply) -> SceneApply.Problem?) {
        _model = State(initialValue: ActionSceneModel(request: request))
        self.onApply = onApply
    }

    private var origin: ProposalPlace? {
        if fromPlan {
            return model.request.currentPlace
        }
        return location.location.map {
            ProposalPlace(name: "今いる所", latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
    }

    private var refreshKey: String {
        "\(location.location != nil)-\(fromPlan)-\(revision)"
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if let input = model.input, !model.ways.isEmpty {
                    SceneMap(input: input, options: model.ways, selectedID: model.selectedID, routes: model.routes) {
                        model.selectedID = $0
                    }
                    .frame(height: typeSize.isAccessibilitySize ? 180 : min(320, geometry.size.height * 0.37))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if let input = model.input {
                            Text(caption(input)).font(Theme.jp(13, .medium)).foregroundStyle(Theme.actionSecondary)
                            if model.usesPlanPlace {
                                Text("今の予定の場所から計算しています")
                                    .font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
                            }
                        }
                        if let selected = model.selected, let input = model.input, previewing {
                            ScenePreview(option: selected, input: input, request: model.request, problem: problem) {
                                apply(selected, input: input)
                            }
                        } else if let selected = model.selected, let input = model.input {
                            SceneWaySummary(option: selected, input: input)
                            Button {
                                problem = nil
                                previewing = true
                            } label: {
                                Text("この案で旅程を確認").font(Theme.jp(16, .bold))
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .foregroundStyle(Theme.surface).background(Theme.ink, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        } else {
                            stateChips
                            content
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .id("\(model.selectedID ?? "")-\(previewing)")
                .background(Theme.surface)
            }
            .background(Theme.surface)
        }
        .task { location.start() }
        .task(id: refreshKey) { await refresh() }
        .sheet(isPresented: $editStates) {
            StateTilesSheet(initial: model.states, initialStrength: model.strength ?? .quite) { states, strength in
                model.edit(states: states, strength: strength)
                editStates = false
                revision += 1
            }
            .presentationDetents([.large])
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(previewing ? "旅程を確認" : model.selected.map { "\($0.id)の案" } ?? "候補を比べる")
                .font(Theme.jp(24, .bold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button(model.selected == nil ? "閉じる" : "戻る") {
                if model.selected == nil {
                    dismiss()
                } else if previewing {
                    previewing = false
                } else {
                    model.selectedID = nil
                }
            }
            .font(Theme.jp(14, .bold)).padding(.horizontal, 16).frame(minHeight: 44)
            .background(Theme.fill, in: .capsule).buttonStyle(.plain)
        }
        .foregroundStyle(Theme.ink)
    }

    private var stateChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(ActionState.allCases.filter { model.states.contains($0) }, id: \.self) { state in
                Button {
                    var updated = model.states
                    updated.remove(state)
                    model.edit(states: updated, strength: state == .tired ? nil : model.strength)
                    revision += 1
                } label: {
                    Text("\(state.label) ×").font(Theme.jp(13, .medium))
                        .padding(.horizontal, 12).frame(minHeight: 44).background(Theme.base, in: .capsule)
                }
                .buttonStyle(.plain).accessibilityLabel("\(state.label)を外す")
            }
            Button("＋追加") { editStates = true }
                .font(Theme.jp(13, .medium)).padding(.horizontal, 14).frame(minHeight: 44)
                .background(Theme.fill, in: .capsule).buttonStyle(.plain)
        }
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .empty:
            message("今の状態を選んでください", detail: "休みたい、食べたいなど、今の状態から案を探します。") {
                action("状態を選ぶ") { editStates = true }
            }
        case .searching:
            HStack(spacing: 12) { ProgressView(); Text("近くの場所と徒歩経路を調べています").font(Theme.jp(14)) }
        case let .needsInput(issue):
            message(issue.message, detail: issue == .needsLocation ? "現在地や、今の予定の場所から探せます。" :
                "旅程で入力してから、もう一度開いてください。時刻や場所は推測で埋めません。") {
                if issue == .needsLocation {
                    if model.request.currentPlace != nil {
                        action("今の予定の場所から探す") { fromPlan = true }
                    }
                    action(location.isAllowed ? "もう一度" : "位置情報を許可する・設定を開く") {
                        if location.status == .notDetermined {
                            location.start()
                        } else if !location.isAllowed,
                                  let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        } else {
                            revision += 1
                        }
                    }
                }
            }
        case .ready:
            results
        }
    }

    @ViewBuilder private var results: some View {
        if model.searchFailed || model.routeFailed {
            message("一部の情報を調べられませんでした", detail: "調べられた場所と経路だけで案を出しています。") {
                action("もう一度") { revision += 1 }
            }
        }
        if model.ways.isEmpty {
            message(model.searchFailed || model.routeFailed ? "案を作れませんでした" : "条件に合う案は見つかりませんでした",
                    detail: "今の状態と次の固定の予定を守る範囲で探しました。") {
                action("状態を選び直す") { editStates = true }
            }
        }
        ForEach(model.ways) { option in
            if !option.way.fits {
                Text("\(option.way.shortfallMinutes)分足りない ・ 固定の時刻は動かしません")
                    .font(Theme.jp(12, .bold)).padding(.top, 8)
            }
            SceneWayRow(option: option, highlighted: option.id == model.ways.first?.id) {
                model.selectedID = option.id
            }
            Divider()
        }
        if !model.ways.isEmpty {
            Text("地図は徒歩経路。時間は目安です。荷物預かり・ロッカーや席の空き・営業時間は確認していません。")
                .font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
        }
    }

    private func caption(_ input: SceneInput) -> String {
        let next = "\(DaySchedule.clock(input.nextStartMinutes)) \(input.nextTitle)（固定）"
        if let stay = input.stay, let opens = stay.checkInMinutes {
            return "次は \(DaySchedule.clock(opens))から \(stay.title) ・ \(next)"
        }
        return "次は \(next)"
    }

    private func refresh() async {
        previewing = false
        let minutes = Trip.minutes(of: .now, on: .now, calendar: .current) ?? 0
        await model.refresh(origin: origin, nowMinutes: minutes, usesPlanPlace: fromPlan)
    }

    /// 「この内容で旅程に入れる」: the itinerary changes only here, and only when it is still the one searched from.
    private func apply(_ option: SceneOption, input: SceneInput) {
        let minutes = Trip.minutes(of: .now, on: .now, calendar: .current) ?? input.nowMinutes
        switch SceneApply.make(
            way: option.way, request: model.request, searchedAtMinutes: input.nowMinutes, nowMinutes: minutes
        ) {
        case let .failure(reason): problem = reason
        case let .success(change): problem = onApply(change)
        }
    }

    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(title, action: perform).font(Theme.jp(14, .bold)).frame(minHeight: 44).buttonStyle(.plain)
    }

    private func message<Actions: View>(_ title: String, detail: String,
                                        @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.jp(16, .bold))
            Text(detail).font(Theme.jp(13)).foregroundStyle(Theme.actionSecondary)
            actions()
        }
        .foregroundStyle(Theme.ink).padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.base, in: .rect(cornerRadius: 18))
    }
}
