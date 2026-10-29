import SwiftUI

/// Figma 25, third version, 04 「旅程を確認」: the way with its times as it would go into the itinerary.
/// Nothing changes until 「この内容で旅程に入れる」 (Notion 02 §6-4 決定 2026-10-27・確定したあとの旅程と元に戻す).
struct ScenePreview: View {
    let option: SceneOption
    let input: SceneInput
    let request: SceneRequest
    let problem: SceneApply.Problem?
    let onApply: () -> Void

    private var added: [SceneStep] {
        option.way.steps.filter(\.isAdded)
    }

    private var skipped: [ItineraryItemSnapshot] {
        guard let ahead = request.ahead(nowMinutes: input.nowMinutes) else { return [] }
        return ahead.between.filter { $0.id != ahead.stay?.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(option.id)  \(option.way.reason.headline)").font(Theme.jp(17, .bold))
            Text(caption).font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                row(time: input.nowMinutes, title: "📍 今いる所", detail: currentDetail, tag: nil)
                ForEach(Array(option.way.steps.enumerated()), id: \.offset) { _, step in
                    Text("徒歩 \(step.walkBeforeMinutes)分").font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
                        .padding(.leading, 60)
                    row(
                        time: step.kind == .next ? input.endMinutes : step.startMinutes,
                        title: "\(step.kind.emoji) \(step.planTitle)", detail: detail(of: step), tag: tag(of: step)
                    )
                }
            }
            if let problem {
                Text(problem.message).font(Theme.jp(13, .bold)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onApply) {
                Text("この内容で旅程に入れる").font(Theme.jp(16, .bold))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(Theme.surface)
                    .background(option.way.fits ? Theme.ink : Theme.actionSecondary, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(!option.way.fits)
            Text("入れたあと、下の通知の「元に戻す」で元の旅程に戻せます。")
                .font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
        }
        .foregroundStyle(Theme.ink)
    }

    private var caption: String {
        var parts: [String] = []
        switch input.end {
        case let .plan(title, _): parts.append("\(DaySchedule.clock(input.endMinutes))の\(title)は動かさない")
        case .checkIn: break
        case .chosen:
            let length = DurationText.text(minutes: input.endMinutes - input.nowMinutes)
            parts.append("\(DaySchedule.clock(input.endMinutes))まで（\(length)）")
        }
        if let opens = input.stay?.checkInMinutes, opens > input.nowMinutes {
            parts.append("\(DaySchedule.clock(opens))より前はチェックインできない")
        }
        let names = added.map(\.planTitle).joined(separator: "・")
        parts.append(added.isEmpty ? "足す予定：なし" : "足す予定：\(added.count)つ（\(names)）")
        parts.append(skipped.isEmpty ? "見送る予定：なし" :
            "見送る予定：\(skipped.map(\.title).joined(separator: "・"))（未定へ移します）")
        return parts.joined(separator: " ・ ")
    }

    private var currentDetail: String? {
        request.current.map { "「\($0.title)」はここで終わりにします（済みにはしません）" }
    }

    private func detail(of step: SceneStep) -> String? {
        let stay = DurationText.text(minutes: step.leaveMinutes - step.startMinutes)
        switch step.kind {
        case .dropLuggage: return step.isUnknown ? "預けられるかは未確認です" : nil
        case .lockerDrop: return "ロッカーの空きは分かりません"
        case .lockerPickUp: return nil
        case .rest, .eat: return "約\(stay)（席の空き・営業時間は分かりません）"
        case .checkIn: return "部屋で休む（約\(stay)）"
        case .next: return "\(DaySchedule.clock(step.arriveMinutes))に着く目安"
        }
    }

    private func tag(of step: SceneStep) -> String? {
        switch step.kind {
        case .checkIn: input.stay?.checkInMinutes.map { "\(DaySchedule.clock($0))から" }
        case .next: "予約"
        default: "追加"
        }
    }

    private func row(time: Int, title: String, detail: String?, tag: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(DaySchedule.clock(time)).font(Theme.latin(13, .bold)).frame(minWidth: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.jp(15, .medium)).fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let tag {
                Text(tag).font(Theme.jp(11, .medium)).padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(Capsule().stroke(Theme.ink, lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
