import SwiftUI

/// Stand-in for parts not built yet (旅程・行きたい・準備・＋). It says so plainly so it is
/// never mistaken for the finished feature; each one is replaced by its own Issue.
struct ComingSoonView: View {
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(Theme.jp(20, .bold))
                .foregroundStyle(Theme.ink)
            Text("これから作ります")
                .font(Theme.jp(14, .medium))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface.ignoresSafeArea())
    }
}
