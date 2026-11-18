#if DEBUG
import MapKit
import SwiftUI

/// Uses the production picture, hours section, and value bars with controlled async responses.
struct LoadingPreviewContent: View {
    let scenario: Int
    let showsDetailSize: Bool
    private let cafe = ProposalPlace(name: "読み込み確認用カフェ", latitude: 35, longitude: 135)
    @State private var model: ActionSceneModel

    init(scenario: Int, showsDetailSize: Bool) {
        self.scenario = scenario
        self.showsDetailSize = showsDetailSize
        let cafe = ProposalPlace(name: "読み込み確認用カフェ", latitude: 35, longitude: 135)
        _model = State(initialValue: ActionSceneModel(
            request: SceneRequest(id: UUID(), plans: [], states: [.wantSit], strength: nil, freeDay: 1),
            routes: SceneRoutes { _, _ in SceneRoute(minutes: 4, polyline: MKPolyline()) },
            search: { _ in [cafe] },
            ai: SceneAI(interpret: { _, _ in nil }, hours: { _, date, _ in
                try? await Task.sleep(for: .seconds(scenario == 0 ? 600 : 1))
                guard !Task.isCancelled, scenario == 1 else { return nil }
                return Self.hours(on: date)
            })
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    LookAroundPicture(place: cafe, height: showsDetailSize ? 160 : 128, loadImage: { _, _ in
                        try? await Task.sleep(for: .seconds(scenario == 0 ? 600 : 1))
                        guard !Task.isCancelled, scenario == 1 else { return nil }
                        return Self.sampleImage()
                    })
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A案 · 歩くのは最小で、座ってゆっくり")
                            .font(Theme.jp(13)).foregroundStyle(Theme.actionSecondary)
                        Text(cafe.name).font(Theme.jp(20, .bold))
                        Text("徒歩4分 · 休憩 約56分").font(Theme.jp(15, .medium))
                    }.padding(16)
                }
                .background(Theme.surface, in: .rect(cornerRadius: 20))
                .clipShape(.rect(cornerRadius: 20))

                if let option = model.ways.first {
                    SceneHoursSection(model: model, option: option, allowed: true, onAllow: {})
                }

                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                    SkeletonBar(width: 30)
                    SkeletonBar(width: 38)
                }
                .padding(12)
                .background(Theme.fill, in: .capsule)
                .accessibilityLabel("移動時間の読み込み表示の見本")
            }
            .padding(12)
        }
        .background(Theme.base, in: .rect(cornerRadius: 20))
        .task {
            model.chosenMinutes = 60
            let origin = ProposalPlace(name: "確認用の出発地", latitude: 34.999, longitude: 135)
            await model.refresh(origin: origin, nowMinutes: 600, usesPlanPlace: false)
            guard !Task.isCancelled, let option = model.ways.first else { return }
            await model.checkHours(for: option)
        }
    }

    private static func hours(on date: Date) -> SceneHours {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return SceneHours(status: "official", date: formatter.string(from: date),
                          timeZone: TimeZone.current.identifier,
                          windows: [.init(start: 540, end: 1080, lastOrder: nil)], closed: false,
                          sources: [.init(url: "https://example.com", title: "開発用の出典", official: true)],
                          checkedAt: ISO8601DateFormatter().string(from: .now))
    }

    private static func sampleImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 600, height: 320)).image { context in
            UIColor.systemGray4.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 320))
            UIColor.systemGray2.setFill()
            for x in stride(from: 40, through: 500, by: 100) {
                context.fill(CGRect(x: x, y: 60, width: 60, height: 140))
            }
            UIColor.systemGray.setFill()
            context.fill(CGRect(x: 0, y: 260, width: 600, height: 60))
        }
    }
}
#endif
