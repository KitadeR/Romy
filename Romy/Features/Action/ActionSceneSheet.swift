import MapKit
import SwiftUI

/// 地図上で比較中の案と、詳細・確定画面への遷移を独立して管理する。
struct ActionSceneSheet: View {
    @State private var model: ActionSceneModel
    @Environment(LocationProvider.self) private var location
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var editStates = false
    @State private var fromPlan = false
    @State private var revision = 0
    @State private var path: [Page] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var replacing: StopSelection?
    @State private var editingLength = false
    @State private var problem: SceneApply.Problem?
    /// Puts the confirmed way into the itinerary; returns why it could not, or nil once it is in.
    let onApply: (SceneApply) -> SceneApply.Problem?

    init(
        request: SceneRequest, facts: LuggageFacts = .off,
        onApply: @escaping (SceneApply) -> SceneApply.Problem?
    ) {
        _model = State(initialValue: ActionSceneModel(request: request, facts: facts))
        self.onApply = onApply
    }

    private var origin: ProposalPlace? {
        if fromPlan {
            return model.request.currentPlace
        }
        return location.location.map {
            ProposalPlace(name: "現在地", latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.surface.ignoresSafeArea()
                if let input = model.input, !model.ways.isEmpty {
                    SceneComparison(model: model, input: input, position: $position) { id in
                        path.append(.detail(id))
                    } header: {
                        controls
                    } footer: {
                        contextFooter(input)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            controls
                            content
                            if model.input?.end == .chosen {
                                ChosenLengthSlider(minutes: $model.chosenMinutes) { revision += 1 }
                            }
                        }.padding(16)
                    }
                }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: Page.self) { page in destination(page) }
        }
        .background(Theme.surface)
        .presentationBackground(Theme.surface)
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

    private var controls: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 10) {
                Button { editStates = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.input.map { $0.origin.name + "周辺" } ?? "候補を比べる")
                                .font(Theme.jp(18, .bold))
                            Text(conditionSummary).font(Theme.jp(12, .medium))
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "pencil").accessibilityHidden(true)
                    }
                    .multilineTextAlignment(.leading).padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(minHeight: 54)
                }
                .buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 20))
                .accessibilityHint("条件を編集")
                Button("閉じる", systemImage: "xmark") {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.regular)
                .frame(minWidth: 44, minHeight: 44)
            }
        }
    }

    private var conditionSummary: String {
        let labels = ActionState.allCases.filter(model.states.contains).map {
            $0 == .tired ? model.strength?.phrase ?? $0.label : $0.label
        }
        return labels.isEmpty ? "今の状態を選ぶ" : labels.joined(separator: "・")
    }

    private func contextFooter(_ input: SceneInput) -> some View {
        VStack(spacing: 2) {
            if input.end == .chosen {
                Button("すごす時間  \(DurationText.text(minutes: model.chosenMinutes))") { editingLength = true }
                    .frame(minHeight: 44)
                    .popover(isPresented: $editingLength) {
                        ChosenLengthSlider(minutes: $model.chosenMinutes) {
                            editingLength = false
                            revision += 1
                        }.padding().presentationCompactAdaptation(.popover)
                    }
            } else {
                Text(caption(input)).multilineTextAlignment(.center)
            }
            if model.usesPlanPlace { Text("予定の場所から計算") }
            if model.searchFailed || model.routeFailed {
                Button("一部の経路・場所を再検索") { revision += 1 }.frame(minHeight: 44)
            }
        }
        .font(Theme.jp(12, .medium)).foregroundStyle(Theme.actionSecondary)
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    @ViewBuilder private func destination(_ page: Page) -> some View {
        switch page {
        case let .detail(id):
            if let option = model.ways.first(where: { $0.id == id }), let input = model.input {
                detail(option, input: input)
            }
        case let .preview(id):
            if let option = model.ways.first(where: { $0.id == id }), let input = model.input {
                ScrollView {
                    ScenePreview(option: option, input: input, request: model.request, problem: problem) {
                        apply(option, input: input)
                    }.padding(20)
                    if problem == .tooLate || problem == .changed {
                        Button(problem == .changed ? "閉じて旅程に戻る" : "もう一度探す") {
                            if problem == .changed { dismiss() } else { revision += 1 }
                        }
                    }
                }
                .toolbarVisibility(.visible, for: .navigationBar)
                .navigationTitle("旅程を確認").navigationBarTitleDisplayMode(.inline)
                .background(Theme.surface)
            }
        }
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
    }

    /// What ends the time: the fixed plan (with the stay before it), the stay's check-in, or the chosen length.
    private func caption(_ input: SceneInput) -> String {
        let stay = input.stay.flatMap { stay in
            stay.checkInMinutes.map { "\(DaySchedule.clock($0))から \(stay.title)" }
        }
        switch input.end {
        case let .plan(title, _):
            let next = "\(DaySchedule.clock(input.endMinutes)) \(title)（固定）"
            return stay.map { "次は \($0) ・ \(next)" } ?? "次は \(next)"
        case .checkIn:
            return "次は \(stay ?? "宿")（このあと時刻の決まった予定はありません）"
        case .chosen:
            return "このあと時刻の決まった予定はありません。すごす時間を選んでください"
        }
    }

    private func refresh() async {
        path = []
        replacing = nil
        position = .automatic
        problem = nil
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

/// 「あと何時間すごす？」: when nothing in the itinerary ends the time, the person chooses how long
/// (2026-10-29, るわさん「わからないならスライドバーで時間を決めれるようにして」). 30 minutes to 5 hours; the ways are
/// made again when the finger lets go.
private struct ChosenLengthSlider: View {
    @Binding var minutes: Int
    let onChosen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("あと").font(Theme.jp(13, .medium))
                Text(DurationText.text(minutes: minutes)).font(Theme.jp(20, .bold))
                Text("すごす").font(Theme.jp(13, .medium))
            }
            Slider(
                value: Binding(get: { Double(minutes) }, set: { minutes = Int($0) }),
                in: Double(ActionSceneModel.chosenRange.lowerBound)...Double(ActionSceneModel.chosenRange.upperBound),
                step: 30
            ) { Text("すごす時間") } minimumValueLabel: {
                Text("30分").font(Theme.jp(11)).foregroundStyle(Theme.actionSecondary)
            } maximumValueLabel: {
                Text("5時間").font(Theme.jp(11)).foregroundStyle(Theme.actionSecondary)
            } onEditingChanged: { editing in
                if !editing { onChosen() }
            }
            .tint(Theme.ink)
            .accessibilityValue(DurationText.text(minutes: minutes))
        }
        .foregroundStyle(Theme.ink)
        .padding(14)
        .background(Theme.base, in: .rect(cornerRadius: 16))
    }
}

// 画面の位置と、差し替え対象の立ち寄り先を区別して持つ。
private extension ActionSceneSheet {
    func detail(_ option: SceneOption, input: SceneInput) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SceneWaySummary(option: option, input: input, footnote: model.footnote) {
                    replacing = StopSelection(id: $0)
                }
                Button("この案で旅程を確認") {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    problem = nil
                    path.append(.preview(option.id))
                }
                .buttonStyle(.glassProminent).buttonSizing(.flexible)
                .controlSize(.large).tint(Theme.ink).disabled(option.isUnavailable)
            }.padding(20)
        }
        .toolbarVisibility(.visible, for: .navigationBar)
        .navigationTitle("案の詳細").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $replacing) { stop in
            SceneReplacementSheet(model: model, option: option, index: stop.id)
        }
        .background(Theme.surface)
    }

    var refreshKey: String {
        "\(fromPlan || location.location != nil)-\(fromPlan)-\(revision)"
    }

    enum Page: Hashable { case detail(String), preview(String) }
    struct StopSelection: Identifiable { let id: Int }
}
