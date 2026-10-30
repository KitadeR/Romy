#if DEBUG
import SwiftData
import SwiftUI

/// Screen 8 uses the current AppShell / ItineraryView with an applied, isolated trip.
struct FenrirCaptureAfterView: View {
    @State private var trip = FenrirCapture.trip(applyingA: true)
    @Environment(\.modelContext) private var context

    var body: some View {
        AppShell(trip: trip, initialTab: .itinerary, initialTravel: FenrirCapture.travel(for: trip))
            .onAppear {
                context.insert(trip)
                recordVerification()
            }
    }
    private func recordVerification() {
        let rows: [[String: Any]] = trip.items.sorted { $0.order < $1.order }.map { item in
            ["title": item.title, "day": item.day as Any? ?? NSNull(),
             "fixedStartMinutes": item.fixedStartMinutes as Any? ?? NSNull(),
             "notBeforeMinutes": item.notBeforeMinutes as Any? ?? NSNull(),
             "durationMinutes": item.durationMinutes, "isDone": item.doneAt != nil]
        }
        let url = URL.temporaryDirectory.appending(path: "fenrir-after-verification.json")
        if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }
}
#endif
