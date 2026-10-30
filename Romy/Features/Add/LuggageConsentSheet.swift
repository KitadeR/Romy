import SwiftUI

/// 「チェックイン前に荷物を預けられるか、前日にRomyが調べておきます」 (Figma 23 2版 05, Notion 02 §6-4): shown once
/// after a stay is added, since the check runs the day before without anything being pressed. 「調べない」 keeps
/// every stay 「？」 and the sheet comes back the next time a stay is added (Notion 05, 2026-10-29).
struct LuggageConsentSheet: View {
    let onAnswer: (LuggageConsent) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("🧳").font(.system(size: 34))
            Text("チェックイン前に荷物を預けられるか、\n前日にRomyが調べておきます")
                .font(Theme.jp(18, .bold)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("荷物が重いときの案を出すために、宿の公式の案内を調べます。")
                .font(Theme.jp(13)).foregroundStyle(Theme.actionSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                row("送るもの", "宿の名前と住所だけ")
                row("送らないもの", "現在地・旅程・ほかの予定")
                row("送り先", "Perplexity（検索AI）")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.base, in: .rect(cornerRadius: 14))
            Text("調べた結果は宿の公開情報としてRomyに30日残り、ほかの人の確認にも使います。")
                .font(Theme.jp(11)).foregroundStyle(Theme.actionSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { onAnswer(.allowed) } label: {
                Text("わかった").font(Theme.jp(16, .bold))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(Theme.surface).background(Theme.ink, in: .capsule)
            }
            .buttonStyle(.plain)
            Button("調べない") { onAnswer(.declined) }
                .font(Theme.jp(14, .medium)).foregroundStyle(Theme.actionSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Theme.ink)
        .background(Theme.surface.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(Theme.jp(12, .medium)).foregroundStyle(Theme.actionSecondary)
                .frame(width: 84, alignment: .leading)
            Text(value).font(Theme.jp(13, .medium)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
