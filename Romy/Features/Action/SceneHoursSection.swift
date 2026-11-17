import SwiftUI

/// 確認できた営業時間と、案の到着・出発時刻を並べて示す。空席の保証とは区別する。
struct SceneHoursSection: View {
    let model: ActionSceneModel
    let option: SceneOption
    let allowed: Bool
    let onAllow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("営業時間").font(Theme.jp(15, .bold))
            ForEach(option.way.steps.filter { $0.kind == .rest || $0.kind == .eat }, id: \.place.scenePlaceKey) { step in
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.place.name).font(Theme.jp(14, .medium))
                    Text("\(DaySchedule.clock(step.startMinutes))到着 · \(DaySchedule.clock(step.leaveMinutes))出発")
                        .font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
                    if model.checkingHours.contains(step.place.scenePlaceKey) {
                        ProgressView("公式の案内を確認中").font(Theme.jp(12))
                    } else if let fact = model.hours[step.place.scenePlaceKey],
                              fact.isFresh(on: model.request.searchDate, at: .now) {
                        Text(fact.caption(for: step)).font(Theme.jp(13, .medium))
                        ForEach(fact.sources, id: \.url) { source in
                            if let url = URL(string: source.url), ["https", "http"].contains(url.scheme) {
                                Link(source.title ?? "確認した公式ページ", destination: url)
                                    .font(Theme.jp(12)).frame(minHeight: 44)
                            }
                        }
                    } else {
                        Text(allowed ? "営業時間を確認できませんでした。Appleマップや公式ページもご確認ください。"
                             : "営業時間はまだ確認していません。")
                            .font(Theme.jp(13)).foregroundStyle(Theme.actionSecondary)
                    }
                }
            }
            if !allowed {
                Button("営業時間を調べる", action: onAllow)
                    .buttonStyle(.glass).font(Theme.jp(13, .medium)).frame(minHeight: 44)
            }
            Text("公開情報をAIで確認しています。臨時変更・空席・当日の受付は保証できません。")
                .font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
        }
        .foregroundStyle(Theme.ink).padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.base, in: .rect(cornerRadius: 16))
    }
}
