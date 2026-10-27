import SwiftUI

extension SceneStep.Kind {
    var emoji: String {
        switch self {
        case .dropLuggage: "🧳"
        case .rest: "☕"
        case .eat: "🍙"
        case .checkIn: "🏨"
        case .lockerDrop, .lockerPickUp: "🔒"
        case .next: "📍"
        }
    }
}

extension SceneWay {
    var stepsCaption: String {
        steps.map { step in
            let title: String = switch step.kind {
            case .dropLuggage: "宿に預ける"
            case .lockerDrop: "預ける"
            case .lockerPickUp: "取る"
            case .checkIn: DaySchedule.clock(step.startMinutes)
            case .next: DaySchedule.clock(step.startMinutes + slackMinutes)
            case .rest, .eat: step.title
            }
            return "\(step.kind.emoji) \(title)\(step.isUnknown ? "？" : "")"
        }.joined(separator: " › ")
    }

    var verificationCaption: String {
        if steps.contains(where: { $0.kind == .dropLuggage && $0.isUnknown }) {
            return "？ 宿で預けられるかは未確認です"
        }
        if steps.contains(where: { $0.kind == .lockerDrop }) {
            return "？ ロッカーの空きは分かりません"
        }
        return "席の空き・営業時間は確かめてください"
    }
}

struct SceneWayRow: View {
    let option: SceneOption
    let highlighted: Bool
    let onSelect: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) { title; sit }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 8) { title; sit }
                        VStack(alignment: .leading, spacing: 8) { title; sit }
                    }
                }
                Text(option.way.stepsCaption).font(Theme.jp(12, .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text("徒歩\(option.way.walkMinutes)分 ・ \(slack) ・ \(option.way.verificationCaption)")
                    .font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? Theme.base : Theme.surface, in: .rect(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .combine)
        .accessibilityHint("この案の要約を表示")
    }

    private var title: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(option.id).font(Theme.latin(12, .bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(Theme.ink, in: .circle)
            Text(option.way.reason.headline).font(Theme.jp(15, .bold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sit: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("約\(DurationText.text(minutes: option.way.sitMinutes))").font(Theme.jp(15, .bold))
            Text("座って休める").font(Theme.jp(10, .medium)).foregroundStyle(Theme.actionSecondary)
        }
        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
    }

    private var slack: String {
        option.way.fits ? "余裕\(option.way.slackMinutes)分" : "\(option.way.shortfallMinutes)分足りない"
    }
}

/// The real times and names behind the summary; this is read-only until the confirmation flow is implemented.
struct SceneWaySummary: View {
    let option: SceneOption
    let input: SceneInput
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(option.id)  \(option.way.reason.headline)").font(Theme.jp(17, .bold))
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { metrics }
            } else {
                HStack(alignment: .top, spacing: 8) { metrics }
            }
            Text(option.way.verificationCaption).font(Theme.jp(13, .medium)).foregroundStyle(Theme.actionSecondary)
            Text("座って休める時間は滞在の目安です。席の空き・営業時間は確認していません。")
                .font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
            Divider()
            Text("手順と時刻").font(Theme.jp(15, .bold))
            ForEach(Array(option.way.steps.enumerated()), id: \.offset) { _, step in
                VStack(alignment: .leading, spacing: 6) {
                    if step.walkBeforeMinutes > 0 {
                        Text("徒歩 \(step.walkBeforeMinutes)分").font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Text(DaySchedule.clock(step.kind == .next ? input.nextStartMinutes : step.startMinutes))
                            .font(Theme.latin(13, .bold)).frame(minWidth: 48, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(step.kind.emoji) \(step.title)\(step.isUnknown ? " ？" : "")")
                                .font(Theme.jp(15, .medium))
                            if step.kind == .next {
                                Text("予約・固定の時刻は動かしません（\(DaySchedule.clock(step.arriveMinutes))到着の目安）")
                                    .font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
                            } else if step.kind == .checkIn, let opens = input.stay?.checkInMinutes {
                                Text(
                                    "\(DaySchedule.clock(opens))から ・ 部屋で約"
                                    + DurationText.text(minutes: step.leaveMinutes - step.startMinutes)
                                )
                                .font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder private var metrics: some View {
        metric("徒歩", "\(option.way.walkMinutes)分")
        metric("座って休める", "約\(DurationText.text(minutes: option.way.sitMinutes))")
        metric("余裕", option.way.fits ? "\(option.way.slackMinutes)分" : "\(option.way.shortfallMinutes)分足りない")
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Theme.jp(11, .medium)).foregroundStyle(Theme.actionSecondary)
            Text(value).font(Theme.jp(16, .bold)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.base, in: .rect(cornerRadius: 12))
    }
}
