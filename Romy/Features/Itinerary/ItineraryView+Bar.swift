import SwiftUI

extension Transaction {
    /// No animation at all, not even the system's own (a sheet slides up unless this is used).
    static var instant: Transaction {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        return transaction
    }
}

/// The four heights the itinerary's sheet rests at, like Rhyme's (Notion 02 §6-5; 2026-10-19): 小 is the name and the
/// menu bar with the map almost whole, 小と中の間 adds the tabs and the first plans, 中 leaves the map the top 30%, and 大
/// is the whole screen. The bar needs about 165pt, so no height is lower.
enum SheetHeights {
    static let low = PresentationDetent.height(165)
    static let small = PresentationDetent.height(380)
    static let middle = PresentationDetent.fraction(0.7)
    static let all: Set<PresentationDetent> = [low, small, middle, .large]

    /// The two heights below the middle, where there is no room for the ＋ menu or a plan's detail.
    static func isLow(_ detent: PresentationDetent) -> Bool { detent == low || detent == small }
}

/// The screen's size and its bottom safe area, measured behind the sheet.
nonisolated struct ScreenMetrics: Equatable, Sendable {
    var width: CGFloat = 0
    var height: CGFloat = 0
    var bottomInset: CGFloat = 0

    init() {}

    init(_ geometry: GeometryProxy) {
        width = geometry.size.width
        height = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
        bottomInset = geometry.safeAreaInsets.bottom
    }
}

/// The height an other tab's sheet was left at, with the tab it belongs to.
struct OtherDetent {
    var key: String?
    var value: PresentationDetent = .large
}

/// How the menu bar is drawn so it looks the same at every sheet height.
struct BarFit {
    var scale: CGFloat = 1
    var shiftX: CGFloat = 0
    var shiftY: CGFloat = 2
}

extension ItineraryView {
    /// The plan's detail has its own buttons at the bottom, so the menu bar is drawn with everything else.
    var showsBar: Bool { !isActive || detailItem == nil }

    /// The itinerary's map, behind the sheet; hidden on the other tabs.
    var mapLayer: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            ItineraryMap(
                trip: trip,
                selection: selection,
                visibleFraction: 0.3,
                aspect: geometry.size.width / (geometry.size.height + insets.top + insets.bottom),
                selectedID: detailID,
                onSelect: openDetail(id:),
                onAddDestination: { isAddingDestinations = true }
            )
            .ignoresSafeArea()
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .onGeometryChange(for: ScreenMetrics.self) { ScreenMetrics($0) } action: { screen = $0 }
        }
    }

    /// What Home's cover and sheet can ask of this sheet.
    var homeActions: HomeActions {
        HomeActions(
            showTrips: { isShowingTrips = true },
            decideDates: { isDecidingDates = true },
            pickPhoto: { isPickingPhoto = true },
            chooseDay: { choosingWish = $0 },
            isExpanded: detent == .large
        )
    }

    /// The sheet's height. The itinerary keeps its own; each other tab starts at the first of its heights. The
    /// set of heights and the selected one change together, so the sheet goes straight to the new height (a
    /// selection that is not in the new set is replaced by whatever the system picks).
    var detent: PresentationDetent {
        get {
            if isActive { return itineraryDetent }
            return otherDetent.key == otherKey ? otherDetent.value : (otherDetents.first ?? .large)
        }
        nonmutating set {
            if isActive {
                itineraryDetent = newValue
            } else {
                otherDetent = OtherDetent(key: otherKey, value: newValue)
            }
        }
    }

    var detentSelection: Binding<PresentationDetent> {
        Binding(get: { detent }, set: { detent = $0 })
    }
}

extension ItineraryView {
    /// Fades the list out behind the menu bar, so the cards' corners do not show beside its rounded ends.
    var barFade: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.surface.opacity(0), location: 0),
                .init(color: Theme.surface.opacity(0.96), location: 0.45),
                .init(color: Theme.surface, location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 170)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }

    /// Scale and offset that put the menu bar at the same size and place on the screen at every sheet height:
    /// it stands 2pt above the full-height sheet's bottom, however the sheet is drawn.
    var barFit: BarFit {
        guard screen.height > 0, sheetLayout.width > 0, sheetFrame.width > 0 else { return BarFit() }
        let drawn = sheetFrame.width / sheetLayout.width
        let target = screen.height - screen.bottomInset - 2
        return BarFit(
            scale: 1 / drawn,
            shiftX: (screen.width / 2 - sheetFrame.midX) / drawn,
            shiftY: (target - sheetFrame.minY) / drawn - sheetLayout.height + 4
        )
    }
}
