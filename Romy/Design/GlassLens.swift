import SwiftUI

/// Where the lens sits among `count` equal choices side by side (the tabs of the menu bar, the ways of going in a
/// move's tiles), and which choice a finger is over.
struct LensTrack: Equatable {
    let count: Int
    let itemWidth: CGFloat
    var spacing: CGFloat = 0

    private var pitch: CGFloat { itemWidth + spacing }

    func offset(of index: Int) -> CGFloat {
        CGFloat(index) * pitch
    }

    /// The choice under `position` (along the track); the ends hold anything beyond them.
    func index(at position: CGFloat) -> Int {
        guard count > 0, pitch > 0 else { return 0 }
        return min(max(Int((position / pitch).rounded(.down)), 0), count - 1)
    }

    /// While a finger drags, the lens's offset so its middle follows `position` without leaving the track.
    func followingOffset(at position: CGFloat) -> CGFloat {
        min(max(position - itemWidth / 2, 0), offset(of: max(count - 1, 0)))
    }
}

/// The glass that marks the chosen one, like the lens of iOS 26's tab bar: a piece of Liquid Glass that is pressed
/// when touched (`interactive`). The caller places it behind the choices and moves it from one to the next.
/// `cornerRadius` nil gives a capsule.
struct GlassLens: View {
    var cornerRadius: CGFloat?

    var body: some View {
        if let cornerRadius {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
    }
}
