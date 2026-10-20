#if DEBUG
import CoreLocation
import MapKit
import SwiftUI

/// DUMMY for the poster (Figma 23案 02・03): nothing here is searched or checked. The texts are fixed, the spinners
/// never finish, and the photos are the study images from Figma (made with image generation, not photos of the shop).
/// Shown only in debug builds, by launching with the environment variable ROMY_MOCK_ACTION23 = checking | result.
/// The facts in the rows were read from the shop's own site on 2026-10-20 (進々堂 shinshindo.jp: ベーカリーレストラン,
/// ホットコーヒーおかわり自由) and from a booking site's listing (hours 7:30〜19:00); the waiting time is not known.
struct ActionCheckMockView: View {
    enum Phase: String {
        /// Figma 23-2: the rows stay grey and spin; nothing moves on.
        case checking
        /// Figma 23-3: ✓ official / ？ / 紹介されています, each with its source tag.
        case result
    }

    let phase: Phase

    static var launchPhase: Phase? {
        ProcessInfo.processInfo.environment["ROMY_MOCK_ACTION23"].flatMap(Phase.init(rawValue:))
    }

    private static let nishiki = CLLocationCoordinate2D(latitude: 35.0050, longitude: 135.7647)
    private static let shinshindo = CLLocationCoordinate2D(latitude: 35.0156, longitude: 135.7672)
    private static let inoda = CLLocationCoordinate2D(latitude: 35.0081, longitude: 135.7632)

    var body: some View {
        ZStack(alignment: .top) {
            map
            sheet
        }
        .background(Theme.base)
        .ignoresSafeArea()
    }

    // MARK: - Map

    private var map: some View {
        Map(
            initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.0129, longitude: 135.7655),
                span: MKCoordinateSpan(latitudeDelta: 0.0235, longitudeDelta: 0.0235)
            )),
            interactionModes: []
        ) {
            MapPolyline(coordinates: [Self.nishiki, Self.shinshindo, Self.inoda])
                .stroke(Theme.ink, lineWidth: 3)
            Annotation("", coordinate: Self.nishiki) { pin("S", filled: true) }
            Annotation("", coordinate: Self.shinshindo) { pin("A", filled: false) }
            Annotation("", coordinate: Self.inoda) { pin("2", filled: true) }
        }
        .frame(height: 340)
        .overlay(alignment: .topLeading) {
            Text("次は15:00 イノダコーヒ本店（固定）")
                .font(Theme.jp(13, .medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 33)
                .background(Capsule().fill(.white))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                .padding(.leading, 20)
                .padding(.top, 70)
        }
    }

    private func pin(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(Theme.latin(13, .bold))
            .foregroundStyle(filled ? .white : Theme.ink)
            .frame(width: 28, height: 28)
            .background(Circle().fill(filled ? Theme.ink : .white))
            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: filled ? 0 : 2))
    }

    // MARK: - Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Theme.faint).frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            header.padding(.top, 14)
            photos.padding(.top, 8)
            Text("錦市場 → 進々堂 寺町店 → 15:00 イノダコーヒ本店")
                .font(Theme.jp(12, .medium))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 8)
            Text("徒歩 合計34分 ・ 次の予定まで26分の余裕")
                .font(Theme.jp(14, .medium))
                .foregroundStyle(Theme.ink)
                .padding(.top, 6)
            fitHeader.padding(.top, 14)
            rows.padding(.top, 10)
            Text(phase == .checking
                 ? "名前・写真・時間は先に読めます。確かめ終わると、上の3行が一度に結果へ変わります。"
                 : "札を押すと出典のページが開きます。AIが調べた情報です。変わっていることがあります。")
                .font(Theme.jp(11, .medium))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            Spacer(minLength: 12)
            Text("この案で旅程を確認")
                .font(Theme.jp(17, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Capsule().fill(Theme.ink))
                .padding(.bottom, 34)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.10), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
        .padding(.top, 330)
    }

    private var header: some View {
        HStack {
            Text("A  進々堂 寺町店の案")
                .font(Theme.jp(20, .bold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            Text("閉じる")
                .font(Theme.jp(14, .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 120, height: 40)
                .background(Capsule().fill(Theme.fill))
        }
    }

    private var photos: some View {
        HStack(spacing: 8) {
            photo("MockBread")
            // 211 : 134 as in Figma, whatever the screen's width.
            photo("MockLawn")
                .containerRelativeFrame(.horizontal) { width, _ in (width - 48) * 134 / 345 }
        }
    }

    private func photo(_ name: String) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .overlay { Image(name).resizable().scaledToFill() }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var fitHeader: some View {
        HStack {
            Text("希望に合うか")
                .font(Theme.jp(16, .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            if phase == .checking {
                HStack(spacing: 6) {
                    MockSpinner(size: 14)
                    Text("確かめています").font(Theme.jp(11, .medium)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch phase {
            case .checking:
                checkingRow("進々堂 寺町店：パンを食べられるか")
                checkingRow("進々堂 寺町店：待ち時間はどれくらいか")
                checkingRow("進々堂 寺町店：いま開いているか")
            case .result:
                resultRow(
                    mark: .official, title: "パンを食べられる",
                    detail: "進々堂 寺町店 ・ 10/20 確認", tag: "公式"
                )
                resultRow(
                    mark: .unknown, title: "待ち時間はどれくらいか",
                    detail: "進々堂 寺町店 ・ この店の待ち時間は確認できませんでした。お店で確かめてね。", tag: nil
                )
                resultRow(
                    mark: .mentioned, title: "7:30〜19:00に開いていると紹介されています",
                    detail: "進々堂 寺町店 ・ 10/20 確認", tag: "ほかの出典"
                )
            }
        }
    }

    private func checkingRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MockSpinner(size: 22)
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(Theme.jp(14, .medium)).foregroundStyle(Theme.secondary)
                SkeletonBar(width: 170, height: 8)
            }
        }
    }

    private enum Mark { case official, unknown, mentioned }

    private func resultRow(mark: Mark, title: String, detail: String, tag: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            markView(mark)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.jp(14, .bold)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(Theme.jp(11, .medium)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let tag {
                Text(tag)
                    .font(Theme.jp(11, .bold))
                    .foregroundStyle(mark == .official ? .white : Theme.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(mark == .official ? Theme.ink : .clear))
                    .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: mark == .official ? 0 : 1))
            }
        }
    }

    @ViewBuilder
    private func markView(_ mark: Mark) -> some View {
        switch mark {
        case .official:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(Theme.ink))
        case .unknown:
            Text("?")
                .font(Theme.latin(12, .bold)).foregroundStyle(Theme.secondary)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Theme.secondary, lineWidth: 1.5))
        case .mentioned:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ink)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.5))
        }
    }
}

/// A ring with a dark arc that turns without end.
private struct MockSpinner: View {
    let size: CGFloat
    @State private var angle = 0.0

    var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.line, lineWidth: 2.5)
            Circle().trim(from: 0, to: 0.28)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(angle))
                .padding(1.25)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { angle = 360 }
        }
        .accessibilityHidden(true)
    }
}
#endif
