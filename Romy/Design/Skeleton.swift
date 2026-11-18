import SwiftUI

/// A placeholder for a value that has not arrived yet; shares the picture loading shimmer.
struct SkeletonBar: View {
    let width: CGFloat
    var height: CGFloat = 10

    var body: some View {
        Capsule()
            .fill(Theme.rangeFill)
            .frame(width: width, height: height)
            .modifier(Shimmer())
            .accessibilityHidden(true)
    }
}
