#if DEBUG
import MapKit
import SwiftUI

/// Deliberately authored display examples (5–7), separate from live candidate search and saved trips.
struct FenrirStoryView: View {
    let initialScreen: Int
    @State private var screen = 5
    @State private var selectedA = true

    var body: some View {
        Group {
            if screen == 8 {
                FenrirCaptureAfterView()
            } else {
                story
            }
        }
        .onAppear { screen = initialScreen }
    }

    private var story: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                FenrirStoryMap(screen: screen, selectedA: selectedA)
                    .frame(height: geometry.size.height * sheetFraction + geometry.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
                VStack {
                    HStack(spacing: 7) {
                        Image(systemName: "lock.fill").font(.system(size: 11))
                        Text("次は17:00 京都駅周辺で夕食（固定）").font(Theme.jp(12, .bold))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.regularMaterial, in: .capsule)
                    Spacer()
                }
                .padding(.top, 8)
                VStack(spacing: 0) {
                    Capsule().fill(.black.opacity(0.2)).frame(width: 36, height: 5).padding(.top, 10).padding(
                        .bottom,
                        13)
                    header.padding(.horizontal, 20).padding(.bottom, 14)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            switch screen {
                            case 5: comparison
                            case 6: detail
                            case 7: preview
                            default: EmptyView()
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 18)
                    }
                    .scrollIndicators(.hidden)
                    if screen == 6 || screen == 7 {
                        Button {
                            screen = screen == 6 ? 7 : 8
                        } label: {
                            Text(screen == 6 ? "この案で旅程を確認" : "この内容で旅程に入れる")
                                .font(Theme.jp(16, .bold)).frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(.white).background(Theme.ink, in: .capsule)
                        }
                        .buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)
                    }
                }
                .background(.white, in: .rect(topLeadingRadius: 30, topTrailingRadius: 30))
                .ignoresSafeArea(edges: .bottom)
                .padding(.top, geometry.size.height * sheetFraction)
            }
            .foregroundStyle(Theme.ink)
            .background(Theme.surface)
        }
    }

    private var sheetFraction: CGFloat { screen >= 7 ? 0.22 : screen == 6 ? 0.25 : 0.26 }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(screen == 5 ? "Romy Now" : screen == 6 ? "\(selectedA ? "A" : "B") の案" : screen == 7 ?
                    "旅程を確認" :
                    "秋の京都旅")
                    .font(Theme.jp(24, .bold))
                Text(screen == 8 ? "10月30日（金） · 1日目" : screen == 7 ? "今の散策は14:00までに短縮" : "14:00 · 京都駅前")
                    .font(Theme.jp(12, .medium)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button(screen == 5 || screen == 8 ? "閉じる" : "戻る") {
                screen = screen == 7 ? 6 : 5
            }
            .font(Theme.jp(13, .bold)).padding(.horizontal, 17).frame(height: 36)
            .background(Theme.fill, in: .capsule).buttonStyle(.plain)
        }
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                pill("🙂 少し疲れた"); pill("🧳 荷物が重い")
            }
            Text("今の状態に合わせた、2つの過ごし方")
                .font(Theme.jp(14, .medium)).padding(.bottom, 2)
            wayCard(isA: true)
            wayCard(isA: false)
            Text("徒歩は館内・地下街の移動を含む目安です。\n席の空きと当日の受付状況は未確認です。")
                .font(Theme.jp(11)).foregroundStyle(Theme.secondary)
        }
    }

    private func wayCard(isA: Bool) -> some View {
        Button {
            selectedA = isA
            screen = 6
        } label: {
            HStack(alignment: .top, spacing: 12) {
                picture(isA: isA).frame(width: 92, height: 110).clipShape(.rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 7) {
                        Text(isA ? "A" : "B").font(Theme.latin(12, .bold)).foregroundStyle(.white)
                            .frame(width: 23, height: 23).background(Theme.ink, in: .circle)
                        Text(isA ? FenrirCapture.titleA : FenrirCapture.titleB)
                            .font(Theme.jp(16, .bold)).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(isA ? "ホテルに荷物を預ける → イノダコーヒ\nポルタ支店で休憩 → チェックイン"
                        : "OGAWA COFFEE 京都駅中央口店\nで休憩 → ホテルへ向かう")
                        .font(Theme.jp(11, .medium)).lineSpacing(3)
                    HStack(spacing: 12) {
                        Label(isA ? "徒歩19分" : "徒歩11分", systemImage: "figure.walk")
                        Text(isA ? "休憩38分" : "休憩56分")
                    }.font(Theme.jp(12, .bold))
                    Text(isA ? "✓ 荷物預かりの公式案内あり" : "荷物は持ったまま、まずひと休み")
                        .font(Theme.jp(10, .medium)).foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12).background(isA ? Theme.fill : .white, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(selectedA ? FenrirCapture.titleA : FenrirCapture.titleB).font(Theme.jp(19, .bold))
            picture(isA: selectedA, verticalOffset: selectedA ? 12 : 0)
                .frame(height: 104).clipShape(.rect(cornerRadius: 17))
            Text(selectedA ? FenrirCapture.cafeA : FenrirCapture.cafeB)
                .font(Theme.jp(13, .bold))
            HStack(spacing: 18) {
                metric(selectedA ? "19分" : "11分", "徒歩の合計")
                metric(selectedA ? "38分" : "56分", "カフェで休憩")
                metric("17:00", "夕食はそのまま")
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedA ? "駅前 → ホテルに荷物を預ける → ポルタB1 → ホテル"
                    : "駅前 → OGAWA COFFEEで休憩 → ホテル")
                    .font(Theme.jp(12, .bold)).fixedSize(horizontal: false, vertical: true)
                Text(selectedA ? "徒歩 5分 ＋ 7分 ＋ 7分 · 館内移動を含む目安"
                    : "徒歩 4分 ＋ 7分 · 館内移動を含む目安")
                    .font(Theme.jp(11)).foregroundStyle(Theme.secondary)
                Text(selectedA ? "14:22–15:00 休憩 → 15:07ごろ チェックイン"
                    : "14:04–15:00 休憩 → 15:07ごろ チェックイン")
                    .font(Theme.jp(12, .medium))
                Text("チェックインは15:00以降。到着時刻は目安です。")
                    .font(Theme.jp(10)).foregroundStyle(Theme.secondary)
            }
            Divider()
            verification
        }
    }

    private var verification: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("確認したこと").font(Theme.jp(14, .bold))
            fact(
                "checkmark.circle.fill",
                "チェックイン前の荷物預かりの案内あり",
                "ホテルグランヴィア京都 · 10/30確認",
                url: "https://jrwest-hotels.jp/granvia-kyoto/stay/service_universal/")
            fact(
                "checkmark.circle",
                selectedA ? "営業時間 8:00–21:00" : "営業時間 7:00–21:00",
                "\(selectedA ? FenrirCapture.cafeA : FenrirCapture.cafeB) · 10/30確認",
                url: selectedA ? "https://www.inoda-coffee.co.jp/shop/poruta/" :
                    "https://www.oc-ogawa.co.jp/shop/")
            Label("席の空き・当日の荷物受付は現地で確認", systemImage: "questionmark.circle")
                .font(Theme.jp(11, .medium)).foregroundStyle(Theme.secondary)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("追加する予定").font(Theme.jp(15, .bold))
            changeCard(
                time: "14:05–14:15",
                title: "ホテルに荷物を預ける",
                subtitle: FenrirCapture.hotel,
                badge: "追加",
                symbol: "suitcase")
            changeCard(
                time: "14:22–15:00",
                title: "カフェで休憩",
                subtitle: FenrirCapture.cafeA,
                badge: "追加",
                symbol: "cup.and.saucer")
            Text("未定へ移す予定").font(Theme.jp(15, .bold))
            changeCard(
                time: "時刻未固定",
                title: "東本願寺を散策",
                subtitle: "削除せず、あとで日に戻せます",
                badge: "未定へ",
                symbol: "arrow.uturn.forward")
            Text("残す予定").font(Theme.jp(15, .bold))
            changeCard(
                time: "15:07ごろ",
                title: "チェックイン",
                subtitle: "\(FenrirCapture.hotel) · 15:00以降",
                badge: "維持",
                symbol: "bed.double")
            changeCard(time: "17:00", title: "京都駅周辺で夕食", subtitle: "固定の時刻は動かしません", badge: "固定", symbol: "lock")
        }
    }

}

extension FenrirStoryView {
    private func picture(isA: Bool, verticalOffset: CGFloat = 0) -> some View {
        Image(uiImage: UIImage(contentsOfFile: Bundle.main.path(
            forResource: isA ? "fenrir-cafe-a" : "fenrir-cafe-b",
            ofType: "png") ?? "") ?? UIImage())
            .resizable().scaledToFill().offset(y: verticalOffset).clipped()
    }

    private func pill(_ text: String) -> some View {
        Text(text).font(Theme.jp(12, .medium)).padding(.horizontal, 11).padding(.vertical, 7).background(
            Theme.fill,
            in: .capsule)
    }

    private func metric(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(Theme.jp(21, .bold)); Text(caption).font(Theme.jp(10)).foregroundStyle(Theme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fact(_ symbol: String, _ title: String, _ note: String, url: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.jp(11, .bold)); Text(note).font(Theme.jp(9)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            Link(destination: URL(string: url)!) {
                Label("公式", systemImage: "arrow.up.right").labelStyle(.titleAndIcon)
            }
            .font(Theme.jp(10, .bold)).tint(Theme.ink)
        }
    }

    private func changeCard(
        time: String,
        title: String,
        subtitle: String,
        badge: String,
        symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 19)).frame(width: 26).padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(time).font(Theme.latin(12, .bold))
                Text(title).font(Theme.jp(14, .bold))
                Text(subtitle).font(Theme.jp(10)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            Text(badge).font(Theme.jp(10, .bold)).padding(.horizontal, 10).padding(.vertical, 5)
                .background(.white, in: .capsule)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(
            Theme.fill,
            in: .rect(cornerRadius: 15))
    }
}
#endif
