import MapKit
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
    /// The place the way adds to sit in (a rest or a meal), whose picture leads the card.
    var seatPlace: ProposalPlace? {
        steps.first { $0.kind == .rest || $0.kind == .eat }?.place
    }

    /// Whether that place is a rest or a meal, for the symbol shown where it has no picture.
    var seatKind: SceneStep.Kind {
        steps.first { $0.kind == .rest || $0.kind == .eat }?.kind ?? .rest
    }

    /// カードでは順序だけを見せ、各地点の時刻は詳細で示す。
    var stopSequence: String {
        steps.map { step in
            switch step.kind {
            case .dropLuggage: "宿に預ける"
            case .rest: "カフェ"
            case .eat: "食事"
            case .checkIn: "宿"
            case .lockerDrop: "ロッカーに預ける"
            case .lockerPickUp: "荷物を受け取る"
            case .next: step.title
            }
        }.joined(separator: " → ")
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

/// One way, floating over the comparison map (Figma MMcgDOW44iAxjwHqqJe4nj 20:257). The picture frame keeps one
/// height in every state, and until the picture is settled the whole card shows as loading.
struct SceneWayCard: View {
    let option: SceneOption
    /// 「候補2件中1件目」, read out in place of the hidden page counter.
    var position = ""
    let open: () -> Void
    @State private var picture = LookAroundPictureModel()

    private var isLoading: Bool {
        guard let place = option.way.seatPlace, case .loading = picture.phase(for: place) else { return false }
        return true
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    if let place = option.way.seatPlace {
                        LookAroundPicture(place: place, kind: option.way.seatKind, height: 128, picture: picture)
                            .id(place.scenePlaceKey)
                    } else {
                        NoPicture(kind: option.way.steps.first?.kind ?? .next, text: "写真はありません", height: 128)
                    }
                }
                .accessibilityHidden(true)
                .padding([.top, .horizontal], 8)
                details
                    .redacted(reason: isLoading ? .placeholder : [])
                    .modifier(LoadingShimmer(isLoading: isLoading))
                    .padding(.horizontal, 16).padding(.bottom, 16)
            }
            // Side by side the cards take the tallest one's height, so a long name never moves the others.
            .frame(maxHeight: .infinity, alignment: .top)
            .foregroundStyle(Theme.ink)
            .background(Theme.surface, in: .rect(cornerRadius: 20))
            .contentShape(.rect(cornerRadius: 20))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue([position, isLoading ? "写真を読み込み中" : ""].filter { !$0.isEmpty }.joined(separator: "、"))
        .accessibilityHint("この案の詳細を表示")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(option.id)案  ·  \(option.way.reason.headline)")
                .font(Theme.jp(13, .medium)).foregroundStyle(Theme.actionSecondary)
            HStack(alignment: .firstTextBaseline) {
                Text(option.way.seatPlace?.name ?? option.way.steps.first?.title ?? option.way.reason.headline)
                    .font(Theme.jp(20, .bold))
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.bold()).accessibilityHidden(true)
            }
            Text("徒歩\(option.way.walkMinutes)分  ·  休憩 約\(DurationText.text(minutes: option.way.sitMinutes))")
                .font(Theme.jp(15, .medium)).monospacedDigit()
            Text(option.way.stopSequence)
                .font(Theme.jp(13)).foregroundStyle(Theme.actionSecondary)
            if !option.way.fits {
                Text("\(option.way.shortfallMinutes)分足りません").font(Theme.jp(14, .bold))
            }
            if let caption = option.luggageCaption {
                Text(caption).font(Theme.jp(13)).foregroundStyle(Theme.actionSecondary)
            } else if option.way.hasUnknown {
                Text(option.way.verificationCaption).font(Theme.jp(13)).foregroundStyle(Theme.actionSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The shared shimmer, only while something is loading.
private struct LoadingShimmer: ViewModifier {
    let isLoading: Bool

    func body(content: Content) -> some View {
        if isLoading { content.modifier(Shimmer()) } else { content }
    }
}

/// The real times and names behind the summary. It changes nothing; the itinerary changes only from `ScenePreview`.
struct SceneWaySummary: View {
    let option: SceneOption
    let input: SceneInput
    let footnote: String
    let onReplace: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Apple's place card open for a place of the way.
    @State private var appleCard: AppleCardItem?
    @State private var picture = LookAroundPictureModel()

    struct AppleCardItem: Identifiable {
        let item: MKMapItem
        var id: ObjectIdentifier { ObjectIdentifier(item) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(option.id)  \(option.way.reason.headline)").font(Theme.jp(17, .bold))
            if let seat = option.way.seatPlace {
                VStack(alignment: .leading, spacing: 8) {
                    LookAroundPicture(place: seat, kind: option.way.seatKind, height: 160, picture: picture)
                        .id(seat.scenePlaceKey)
                    if seat.placeID != nil { appleCardButton(seat) }
                }
            }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { metrics }
            } else {
                HStack(alignment: .top, spacing: 8) { metrics }
            }
            if case .checked(let fact) = option.luggage {
                LuggageFactDetail(fact: fact)
            } else if option.luggageCaption != nil || option.way.hasUnknown {
                Text(option.luggageCaption ?? option.way.verificationCaption)
                    .font(Theme.jp(13, .medium)).foregroundStyle(Theme.actionSecondary)
            }
            Text(footnote)
                .font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
            Divider()
            Text("手順と時刻").font(Theme.jp(15, .bold))
            ForEach(Array(option.way.steps.enumerated()), id: \.offset) { index, step in
                VStack(alignment: .leading, spacing: 6) {
                    if step.walkBeforeMinutes > 0 {
                        Text("徒歩 \(step.walkBeforeMinutes)分").font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Text(DaySchedule.clock(step.kind == .next ? input.endMinutes : step.startMinutes))
                            .font(Theme.latin(13, .bold)).frame(minWidth: 48, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(step.kind.emoji) \(step.title)\(step.isUnknown ? " ？" : "")")
                                .font(Theme.jp(15, .medium))
                            if step.kind == .rest || step.kind == .eat {
                                Button(step.kind == .eat ? "別の食事先を探す" : "別のカフェを探す") {
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                    onReplace(index)
                                }
                                    .font(Theme.jp(14, .medium)).buttonStyle(.glass).tint(Theme.ink)
                                    .disabled(option.isUnavailable)
                            }
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
        .sheet(item: $appleCard) { card in
            AppleMapItemDetail(item: card.item) { appleCard = nil }
                .presentationDetents([.medium, .large])
        }
    }

    /// 「写真・営業時間を見る」: Apple's own place card, where the place's photos and hours are.
    private func appleCardButton(_ place: ProposalPlace) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            Task {
                if let item = await PlacePhotos.mapItem(of: place) { appleCard = AppleCardItem(item: item) }
            }
        } label: {
            Label("\(place.name)の写真・営業時間（Appleマップ）", systemImage: "photo.on.rectangle")
                .font(Theme.jp(12, .medium))
                .multilineTextAlignment(.leading)

        }
        .buttonStyle(.glass)
        .controlSize(.regular)
        .frame(minHeight: 44)
    }

    @ViewBuilder private var metrics: some View {
        metric("徒歩", "\(option.way.walkMinutes)分")
        metric("座って休める", "約\(DurationText.text(minutes: option.way.sitMinutes))")
        // Spare minutes only mean something when the way walks to a fixed plan at the end.
        if option.way.endsAtPlan || !option.way.fits {
            metric("余裕", option.way.fits ? "\(option.way.slackMinutes)分" : "\(option.way.shortfallMinutes)分足りない")
        }
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

/// The check under a summary (Figma 23 2版 04): the line, the source tag that opens the page, the date it was
/// checked, the conditions the source writes, and what was not checked.
struct LuggageFactDetail: View {
    let fact: LuggageFact
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(fact.caption).font(Theme.jp(13, .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let source = fact.sources.first, let url = URL(string: source.url) {
                    Button { openURL(url) } label: {
                        Text(source.official ? "公式" : "ほかの出典").font(Theme.jp(11, .medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .foregroundStyle(source.official ? Theme.surface : Theme.ink)
                            .background(source.official ? Theme.ink : Theme.base, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(source.official ? "公式の出典を開く" : "ほかの出典を開く")
                }
                Text(fact.checkedDateText()).font(Theme.jp(11)).foregroundStyle(Theme.actionSecondary)
            }
            if !fact.conditions.isEmpty {
                Text(fact.conditions.joined(separator: " ・ ")).font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if fact.result == .official || fact.result == .introduced || fact.hasLocker {
                Text("当日に受け付けてもらえるかは確かめていません").font(Theme.jp(12)).foregroundStyle(Theme.actionSecondary)
            }
            Text("AIが調べた情報です。変わっていることがあります。").font(Theme.jp(11)).foregroundStyle(Theme.actionSecondary)
        }
        .foregroundStyle(Theme.ink)
    }
}
