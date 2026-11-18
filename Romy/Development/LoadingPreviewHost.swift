#if DEBUG
import SwiftUI

/// An explicit launch mode for checking slow responses without using saved trips or live services.
struct LoadingPreviewHost: View {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-loading-preview") }

    @State private var scenario = 0
    @State private var showsDetailSize = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("取得状態", selection: $scenario) {
                    Text("取得中").tag(0)
                    Text("取得成功").tag(1)
                    Text("画像なし").tag(2)
                }
                .pickerStyle(.segmented)
                Toggle("詳細の写真サイズ", isOn: $showsDetailSize)
                LoadingPreviewContent(scenario: scenario, showsDetailSize: showsDetailSize)
                    .id(scenario)
            }
            .padding(20)
            .background(Theme.surface)
            .navigationTitle("読み込み表示の確認")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Text("開発用の表示です。保存・通信は行いません。")
                    .font(Theme.jp(11)).foregroundStyle(Theme.actionSecondary).padding(8)
            }
        }
    }
}
#endif
