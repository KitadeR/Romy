#if DEBUG
import SwiftData
import SwiftUI

struct ScreenshotHost: View {
    @State private var trip = ScreenshotScene.trip()
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            switch ScreenshotScene.screen ?? 2 {
            case 1:
                TripCreationView(model: ScreenshotScene.creation()) { _ in }
            case 4:
                StateTilesSheet(
                    initial: [.tired, .heavyLuggage],
                    initialStrength: .little,
                    initiallyAskingStrength: true) { _, _ in }
            case 8:
                ScreenshotAfterView()
            case 2, 3:
                AppShell(
                    trip: trip,
                    initialTab: ScreenshotScene.screen == 3 ? .itinerary : .home,
                    initialTravel: ScreenshotScene.travel(for: trip))
            default:
                ScreenshotStoryView(initialScreen: ScreenshotScene.screen ?? 5)
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            context.insert(trip)
        }
    }
}
#endif
