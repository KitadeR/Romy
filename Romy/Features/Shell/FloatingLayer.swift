import SwiftData
import SwiftUI
import UIKit

/// The menu bar and ＋ float in a window of their own over the itinerary's sheet (2026-10-29), so the sheet's
/// heights and the way iOS draws a sheet that is not full height never move or scale them. Touches go through
/// to the screen below except on the bar, the ＋ and what the ＋ opens. The bar steps aside while something
/// else is shown over the sheet (the trips, a time, the scenes of Romy Now), as it did when it lived inside it.
struct FloatingLayer<Content: View>: View {
    let isShown: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.modelContext) private var modelContext
    @Environment(LocationProvider.self) private var location
    @State private var hitArea = FloatingHitArea()

    var body: some View {
        FloatingWindow(
            isShown: isShown,
            hitArea: hitArea,
            content: AnyView(
                content()
                    .environment(\.modelContext, modelContext)
                    .environment(location)
                    .environment(hitArea)
            )
        )
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }
}

/// Where the floating layer takes touches, on the screen: the bar with the ＋, or everything while the ＋ is open.
@Observable
final class FloatingHitArea {
    @ObservationIgnored var rect: CGRect = .null
}

private struct FloatingWindow: UIViewRepresentable {
    let isShown: Bool
    let hitArea: FloatingHitArea
    let content: AnyView

    func makeCoordinator() -> Coordinator { Coordinator(hitArea: hitArea, content: content) }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onWindow = { [weak coordinator = context.coordinator] window in coordinator?.attach(to: window) }
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        context.coordinator.update(content: content, isShown: isShown)
    }

    static func dismantleUIView(_ uiView: AnchorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Tells when it is in the app's window, so the floating window can join the same scene.
    final class AnchorView: UIView {
        var onWindow: (UIWindow) -> Void = { _ in }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { onWindow(window) }
        }
    }

    final class Coordinator {
        private let hitArea: FloatingHitArea
        private let hosting: UIHostingController<AnyView>
        private var window: PassthroughWindow?
        private weak var appWindow: UIWindow?
        private var link: CADisplayLink?
        private var isShown = true
        private var isCovered = false

        init(hitArea: FloatingHitArea, content: AnyView) {
            self.hitArea = hitArea
            hosting = UIHostingController(rootView: content)
            hosting.view.backgroundColor = .clear
        }

        func attach(to appWindow: UIWindow) {
            guard window == nil, let scene = appWindow.windowScene else { return }
            self.appWindow = appWindow
            let window = PassthroughWindow(windowScene: scene)
            window.hitArea = hitArea
            window.windowLevel = appWindow.windowLevel + 1
            window.backgroundColor = .clear
            window.rootViewController = hosting
            window.isHidden = false
            self.window = window
            let link = CADisplayLink(target: self, selector: #selector(watch))
            link.add(to: .main, forMode: .common)
            self.link = link
            apply(animated: false)
        }

        func update(content: AnyView, isShown: Bool) {
            hosting.rootView = content
            guard isShown != self.isShown else { return }
            self.isShown = isShown
            apply(animated: true)
        }

        func detach() {
            link?.invalidate()
            link = nil
            window?.isHidden = true
            window = nil
        }

        /// Something presented over the itinerary's sheet covers the bar, as the sheet itself did before.
        @objc private func watch() {
            let sheet = appWindow?.rootViewController?.presentedViewController
            let covered = sheet?.presentedViewController != nil
            guard covered != isCovered else { return }
            isCovered = covered
            apply(animated: true)
        }

        private func apply(animated: Bool) {
            let visible = isShown && !isCovered
            window?.isUserInteractionEnabled = visible
            let change = { self.hosting.view.alpha = visible ? 1 : 0 }
            if animated {
                UIView.animate(withDuration: 0.2, animations: change)
            } else {
                change()
            }
        }
    }
}

/// Takes only the touches on the floating bar and ＋; the rest reach the app below.
private final class PassthroughWindow: UIWindow {
    weak var hitArea: FloatingHitArea?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Sheets opened from the ＋ are presented in this window and take every touch.
        if rootViewController?.presentedViewController != nil { return super.hitTest(point, with: event) }
        guard let rect = hitArea?.rect, rect.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}
