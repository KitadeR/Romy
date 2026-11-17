#if DEBUG
import SwiftData
import SwiftUI

struct FenrirCaptureHost: View {
    @State private var trip = FenrirCapture.trip()
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            switch FenrirCapture.screen ?? 2 {
            case 1:
                TripCreationView(model: FenrirCapture.creation()) { _ in }
            case 4:
                StateTilesSheet(
                    initial: [.tired, .heavyLuggage],
                    initialStrength: .little,
                    initiallyAskingStrength: true) { _, _ in }
            case 8:
                FenrirCaptureAfterView()
            case 2, 3:
                AppShell(
                    trip: trip,
                    initialTab: FenrirCapture.screen == 3 ? .itinerary : .home,
                    initialTravel: FenrirCapture.travel(for: trip))
            default:
                FenrirStoryView(initialScreen: FenrirCapture.screen ?? 5)
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            context.insert(trip)
        }
    }
}
#endif
