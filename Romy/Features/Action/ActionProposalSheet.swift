import SwiftUI

/// 「候補を比べる」 (Notion 02 §6-4; Figma 24案 01–04). The chips and condition tags are on top, below them the
/// ways found: with how long they take and how many minutes they are short; or the reason none was found, with
/// the next thing to do. Not yet: photos, the map, checking a way (23案), and 「この案で旅程を確認」.
struct ActionProposalSheet: View {
    @State var model: ActionProposalModel
    let location: LocationProvider
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isAdding = false
    @State private var draft = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    wishRow
                    if isAdding { addField }
                    content
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.surface.ignoresSafeArea())
        .task(id: model.originKey) { await model.refresh() }
    }

    // MARK: - Top

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("候補を比べる").font(Theme.jp(26, .bold)).foregroundStyle(Theme.ink)
                Text(nextCaption).font(Theme.jp(13, .medium)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Button("閉じる") { dismiss() }
                .font(Theme.jp(14, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Capsule().fill(Theme.fill))
                .buttonStyle(.plain)
        }
    }

    /// 「次は15:00 麦の湯（固定）」
    private var nextCaption: String {
        let opportunity = model.opportunity
        let clock = DaySchedule.clock(opportunity.nextStartMinutes)
        return "次は\(clock) \(opportunity.nextTitle)（\(opportunity.nextIsFixed ? "固定" : "目安")）"
    }

    private var wishRow: some View {
        FlowLayout(spacing: 8) {
            ForEach(model.chips, id: \.text) { chip in
                HStack(spacing: 8) {
                    Text(chip.text).font(Theme.jp(14, .medium))
                    Button { model.remove(chip) } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(chip.text)を外す")
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Capsule().fill(Theme.fill))
            }
            ForEach(model.conditions, id: \.text) { condition in
                HStack(spacing: 6) {
                    Text(condition.text).font(Theme.jp(12, .medium))
                    Button { model.remove(condition) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(condition.text)を外す")
                }
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(Theme.fill))
            }
            Button {
                isAdding = true
                isTyping = true
            } label: {
                Text("＋追加").font(Theme.jp(14, .medium)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(Capsule().fill(Theme.fill))
            }
            .buttonStyle(.plain)
        }
    }

    private var addField: some View {
        HStack {
            TextField("やりたいこと（例：パンを買う）", text: $draft)
                .font(Theme.jp(15, .medium))
                .focused($isTyping)
                .submitLabel(.done)
                .onSubmit(commitDraft)
            Button("追加", action: commitDraft)
                .font(Theme.jp(14, .bold))
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func commitDraft() {
        model.add(draft)
        draft = ""
        isAdding = false
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .empty:
            note("やりたいことを入れてください。例：パンを買う、海で食べる、あまり歩きたくない")
        case .searching:
            HStack(spacing: 10) {
                ProgressView()
                Text("探しています").font(Theme.jp(14, .medium)).foregroundStyle(Theme.secondary)
            }
            .padding(.top, 8)
        case .needsLocation:
            locationCard
        case .done:
            if let outcome = model.outcome { results(outcome) }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Theme.jp(14, .medium)).foregroundStyle(Theme.secondary).padding(.top, 8)
    }

    /// Figma 24案 02: the permission is asked for by the system's own dialog, so this only points to it.
    /// When it is already given, the place is only not known yet, and Settings would not help.
    private var locationCard: some View {
        messageCard(
            title: "今いる場所が分かりません",
            detail: location.isAllowed
                ? "位置情報は許可されています。場所が分かるまで少し待つか、位置を使わずにほかの場所から探せます。"
                : "近くを探すには位置情報が必要です。位置を使わずに、ほかの場所から探すこともできます。"
        ) {
            if model.canUsePlanPlace {
                actionButton("今の予定の場所（\(model.opportunity.currentTitle)）から") { model.startFromPlan() }
            }
            if !location.isAllowed {
                actionButton(location.status == .notDetermined ? "位置情報を許可する" : "設定を開く") { allowLocation() }
            }
        }
    }

    private func allowLocation() {
        if location.status == .notDetermined {
            location.start()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    @ViewBuilder
    private func results(_ outcome: ActionProposalOutcome) -> some View {
        if !outcome.chipsFailed.isEmpty { failedCard(outcome) }
        if !outcome.chipsWithoutPlaces.isEmpty { noPlacesCard(outcome) }
        let firstShort = outcome.combinations.firstIndex { !$0.fits && !$0.missingWalk }
        ForEach(Array(outcome.combinations.enumerated()), id: \.offset) { index, way in
            if !way.fits, !way.missingWalk { shortBand(way, explains: index == firstShort) }
            wayCard(way, letter: ActionProposalModel.letter(index))
        }
    }

    // MARK: - Cards

    /// Figma 24案 01: nothing was found near, said plainly, with what to do next.
    private func noPlacesCard(_ outcome: ActionProposalOutcome) -> some View {
        let names = outcome.chipsWithoutPlaces.map { ActionProposalModel.stem($0.text) }.joined(separator: "・")
        let walk = "歩いて片道\(model.limitMinutes)分まで\(model.isWalkingLess ? "（歩くのは少なめ）" : "")で探しました。"
        let rest = outcome.combinations.isEmpty ? "" : "見つかったものだけで案を出しています。"
        return messageCard(title: "近くに\(names)は見つかりませんでした", detail: walk + rest) {
            actionButton("もう少し遠くも") { model.searchWider() }
            if let chip = outcome.chipsWithoutPlaces.first {
                actionButton("\(ActionProposalModel.stem(chip.text))を外す") { model.remove(chip) }
            }
            actionButton("希望を変える") {
                isAdding = true
                isTyping = true
            }
        }
    }

    /// Figma 24案 04: the places that were found stay, the ones that could not be asked for are named.
    private func failedCard(_ outcome: ActionProposalOutcome) -> some View {
        let names = outcome.chipsFailed.map { ActionProposalModel.stem($0.text) }.joined(separator: "・")
        return messageCard(title: "\(names)の候補を調べられませんでした", detail: "通信がつながりませんでした。") {
            actionButton("もう一度") { model.rerun() }
        }
    }

    /// 「12分足りない  15:00の予約は動かしません」 (Figma 24案 03).
    /// The note that the next plan is not moved is said once, on the first way that is short.
    private func shortBand(_ way: ActionCombination, explains: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(way.shortfallMinutes)分足りない")
                .font(Theme.jp(12, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1))
            if explains, model.opportunity.nextIsFixed {
                Text("\(DaySchedule.clock(model.opportunity.nextStartMinutes))の\(model.opportunity.nextTitle)は動かしません")
                    .font(Theme.jp(12, .medium))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private func wayCard(_ way: ActionCombination, letter: String) -> some View {
        let route = (way.stops.map(\.place.name) + [model.opportunity.nextTitle]).joined(separator: " → ")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(letter)
                    .font(Theme.latin(13, .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.ink))
                Text(way.stops.first?.place.name ?? "").font(Theme.jp(18, .bold)).foregroundStyle(Theme.ink)
            }
            Text(way.stops.map(\.chip.text).joined(separator: "・"))
                .font(Theme.jp(12, .medium))
                .foregroundStyle(Theme.ink)
            Text(route).font(Theme.jp(12, .medium)).foregroundStyle(Theme.secondary)
            Text(timeLine(way)).font(Theme.jp(12, .bold)).foregroundStyle(way.fits ? Theme.ink : Theme.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func timeLine(_ way: ActionCombination) -> String {
        if way.missingWalk { return "歩く時間を調べられませんでした" }
        var walk = "徒歩 合計\(DurationText.text(minutes: way.walkMinutes))"
        // The walk to the next plan is needed anyway; say how much of the total the detour adds.
        if let detour = way.detourWalkMinutes, detour > 0 {
            walk += "(うち寄り道 +\(DurationText.text(minutes: detour)))"
        }
        if way.walksMoreThanAsked { walk += " ・ 歩くのは少なめより多め" }
        // A way that is short says how short on the band above it, not again here.
        return way.fits ? "\(walk) ・ 予定まで\(DurationText.text(minutes: way.slackMinutes))の余裕" : walk
    }

    private func messageCard<Buttons: View>(
        title: String, detail: String, @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.jp(17, .bold)).foregroundStyle(Theme.ink)
            Text(detail).font(Theme.jp(13, .medium)).foregroundStyle(Theme.secondary)
            FlowLayout(spacing: 8) { buttons() }.padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.jp(13, .bold)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Capsule().fill(Theme.fill))
        }
        .buttonStyle(.plain)
    }
}
