import SwiftUI

/// Moves only the highlight, leaving the placeholder's size and the surrounding content still.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isMoving = false

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion, scenePhase == .active {
                GeometryReader { geometry in
                    let bandWidth = geometry.size.width * 0.6
                    LinearGradient(
                        colors: [.clear, Theme.surface.opacity(0.85), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: bandWidth)
                    .offset(x: isMoving ? geometry.size.width : -bandWidth)
                    .animation(.linear(duration: 1.2).delay(0.2).repeatForever(autoreverses: false), value: isMoving)
                    .onAppear { isMoving = true }
                    .onDisappear { isMoving = false }
                }
                .mask(content)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}
