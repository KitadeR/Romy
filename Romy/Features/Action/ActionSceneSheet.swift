import MapKit
import SwiftUI

/// 地図上で比較中の案と、詳細・確定画面への遷移を独立して管理する。
struct ActionSceneSheet: View {
    @State private var model: ActionSceneModel
    @Environment(LocationProvider.self) private var location
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var editStates = false
    @State private var editedNote = ""
    @State private var chosenOrigin: ProposalPlace?
    @State private var choosingOrigin = false
    @State private var refinement: ActionSceneModel.Refinement?
    @State private var explainsHours = false
    @State private var promptedHours = false
    @AppStorage("romy.scene.hoursConsent") private var hoursConsent = false
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
        if let chosenOrigin { return chosenOrigin }
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
                    } notice: {
                        sceneNotices
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            controls
                            content
                            if model.noteFailed {
                                Text("一言を読み取れませんでした。内容を短くするか、状態を選んでお試しください。")
                                    .font(Theme.jp(13)).foregroundStyle(Theme.actionSecondary)
                            }
                            if !model.preferences.unhandled.isEmpty {
                                Text("未反映：" + model.preferences.unhandled.joined(separator: "・"))
                                    .font(Theme.jp(13)).foregroundStyle(Theme.actionSecondary)
                            }
                            if model.input?.end == .chosen, model.preferences.totalMinutes == nil {
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
            StateTilesSheet(initial: model.states, initialStrength: model.strength ?? .quite,
                            initialNote: model.note, onNoteChange: { editedNote = $0 }) { states, strength in
                model.edit(states: states, strength: strength, note: editedNote)
                refinement = nil
                editStates = false
                revision += 1
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $choosingOrigin) {
            SceneOriginPicker { place in
                chosenOrigin = place; fromPlan = false; refinement = nil; revision += 1
            }
        }
        .alert("この店の営業時間を調べる", isPresented: $explainsHours) {
            Button("同意して調べる") { hoursConsent = true }
            Button("今はしない", role: .cancel) { }
        } message: {
            Text("店舗の名前・住所・対象日をRomyの中継サーバー経由でPerplexityの検索AIへ送ります。旅程全体や現在地は送りません。公式情報でも臨時変更や空席は保証できません。1回のRomy Nowで荷物預かりと合わせて3回まで確認します。")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 10) {
                    Button { editedNote = model.note; editStates = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.input.map { $0.origin.name + "周辺" } ?? "候補を比べる")
                                    .font(Theme.jp(16, .bold))
                                Text(conditionSummary).font(Theme.jp(12, .medium))
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "pencil").accessibilityHidden(true)
                        }
                        .multilineTextAlignment(.leading).padding(.horizontal, 8)
                    }
                    .buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: 20)).controlSize(.regular)
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
            if !model.ways.isEmpty { refinementControls }
            conditionChips
        }
    }

    private var conditionSummary: String {
        let labels = ActionState.allCases.filter(model.states.contains).map {
            $0 == .tired ? model.strength?.phrase ?? $0.label : $0.label
        }
        return labels.isEmpty ? (model.note.isEmpty ? "今の状態を選ぶ" : "一言の条件で探す")
            : labels.joined(separator: "・")
    }

    /// What used to sit in a band under the cards, shown above them only while it applies.
    @ViewBuilder private var sceneNotices: some View {
        VStack(spacing: 6) {
            if model.isRefining {
                notice { HStack(spacing: 8) { ProgressView().controlSize(.mini); Text("候補を絞り直しています") } }
            }
            if let message = model.refinementMessage { notice { Text(message) } }
            if model.noteFailed { notice { Text("一言を読み取れませんでした。状態の条件で探しています。") } }
            if !model.preferences.unhandled.isEmpty {
                notice { Text("未反映：" + model.preferences.unhandled.joined(separator: "・")) }
            }
            if model.usesPlanPlace { notice { Text("予定の場所から計算") } }
            if model.searchFailed || model.routeFailed {
                Button("一部の経路・場所を再検索") { revision += 1 }
                    .font(Theme.jp(12, .bold)).buttonStyle(.glass).frame(minHeight: 44)
            }
        }
        .multilineTextAlignment(.center)
    }

    private func notice<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(Theme.jp(12, .bold)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
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
                    ScenePreview(option: option, input: input, request: model.request, problem: problem,
                                 hoursPermit: model.hoursPermit(option), checkingHours: model.isCheckingHours(for: option)) {
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
                    action("場所を選んで探す") { choosingOrigin = true }
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
        if refinement == nil {
            path = []; replacing = nil; position = .automatic; problem = nil
        }
        let minutes = Trip.minutes(of: .now, on: .now, calendar: .current) ?? 0
        await model.refresh(origin: origin, nowMinutes: minutes, usesPlanPlace: fromPlan, refinement: refinement)
        refinement = nil
    }

    /// 「この内容で旅程に入れる」: the itinerary changes only here, and only when it is still the one searched from.
    private func apply(_ option: SceneOption, input: SceneInput) {
        guard model.hoursPermit(option), !model.isCheckingHours(for: option) else { return }
        guard Calendar.current.isDateInToday(model.request.searchDate) else { problem = .tooLate; return }
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
    var refinementControls: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Group {
                    Button("もっと近く", systemImage: "location") { refine(.closer) }
                    Button("ほかの候補", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") { refine(.others) }
                }
                .disabled(model.isRefining)
                if let input = model.input { timeChip(input) }
            }
            .font(Theme.jp(13, .medium)).buttonStyle(.glass).controlSize(.regular)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    /// The time the ways fill, next to the refinements (it used to sit in the band under the cards).
    @ViewBuilder func timeChip(_ input: SceneInput) -> some View {
        if let total = model.preferences.totalMinutes {
            timeLabel("上限 " + DurationText.text(minutes: total))
                .accessibilityLabel("使える時間 " + DurationText.text(minutes: total) + "、移動を含む上限")
        } else if input.end == .chosen {
            Button(DurationText.text(minutes: model.chosenMinutes), systemImage: "clock") { editingLength = true }
                .accessibilityLabel("すごす時間 " + DurationText.text(minutes: model.chosenMinutes))
                .accessibilityHint("すごす時間を変える")
                .popover(isPresented: $editingLength) {
                    ChosenLengthSlider(minutes: $model.chosenMinutes) {
                        editingLength = false
                        revision += 1
                    }.padding().presentationCompactAdaptation(.popover)
                }
        } else {
            timeLabel(untilText(input)).accessibilityLabel(caption(input))
        }
    }

    /// 「15:00 京都駅まで」: the short form of `caption`, for the chip.
    func untilText(_ input: SceneInput) -> String {
        switch input.end {
        case let .plan(title, _): "\(DaySchedule.clock(input.endMinutes)) \(title)まで"
        case .checkIn: "\(DaySchedule.clock(input.endMinutes)) \(input.stay?.title ?? "宿")まで"
        case .chosen: DurationText.text(minutes: model.chosenMinutes)
        }
    }

    func timeLabel(_ text: String) -> some View {
        Label(text, systemImage: "clock")
            .lineLimit(1)
            .padding(.horizontal, 14).frame(minHeight: 36)
            .glassEffect(.regular, in: .capsule)
    }

    @ViewBuilder var conditionChips: some View {
        if !model.preferences.captions.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(model.preferences.captions.enumerated()), id: \.offset) { index, caption in
                        Button {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            model.removeCondition(at: index); refinement = nil; revision += 1
                        } label: {
                            Label(caption, systemImage: "xmark").font(Theme.jp(12, .medium))
                        }.buttonStyle(.glass).accessibilityLabel(caption + "の条件を外す")
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    func refine(_ kind: ActionSceneModel.Refinement) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        refinement = kind; revision += 1
    }

    func detail(_ option: SceneOption, input: SceneInput) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SceneWaySummary(option: option, input: input, footnote: model.footnote) {
                    replacing = StopSelection(id: $0)
                }
                SceneHoursSection(model: model, option: option, allowed: hoursConsent) { explainsHours = true }
                Button("この案で旅程を確認") {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    problem = nil
                    path.append(.preview(option.id))
                }
                .buttonStyle(.glassProminent).buttonSizing(.flexible)
                .controlSize(.large).tint(Theme.ink)
                .disabled(option.isUnavailable || !model.hoursPermit(option)
                          || model.isCheckingHours(for: option) || !option.way.fits)
            }.padding(20)
        }
        .toolbarVisibility(.visible, for: .navigationBar)
        .navigationTitle("案の詳細").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $replacing) { stop in
            SceneReplacementSheet(model: model, option: option, index: stop.id)
        }
        .background(Theme.surface)
        .task(id: "\(option.way.seatPlace?.scenePlaceKey ?? "")-\(hoursConsent)") {
            if hoursConsent { await model.checkHours(for: option) }
            else if !promptedHours { promptedHours = true; explainsHours = true }
        }
    }

    var refreshKey: String {
        "\(fromPlan || chosenOrigin != nil || location.location != nil)-\(fromPlan)-\(revision)"
    }

    enum Page: Hashable { case detail(String), preview(String) }
    struct StopSelection: Identifiable { let id: Int }
}
