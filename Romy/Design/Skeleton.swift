import SwiftUI

/// A grey bar that stands where a value is still being loaded and slowly dims and brightens
/// (Notion 02 §6-3 「読み込み中は灰色の骨組み」, like Rhyme). It carries no text, so nothing is made up.
struct SkeletonBar: View {
    let width: CGFloat
    var height: CGFloat = 10

    @State private var isDim = false

    var body: some View {
        Capsule()
            .fill(Theme.faint)
            .frame(width: width, height: height)
            .opacity(isDim ? 0.35 : 0.9)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { isDim = true }
            }
            .accessibilityHidden(true)
    }
}
