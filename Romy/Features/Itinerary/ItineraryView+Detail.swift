import SwiftUI

extension ItineraryView {
    /// Opens a plan's detail; it needs room, so a small sheet rises to the middle height.
    func openDetail(_ item: ItineraryItem) {
        // The map has to stay in view: from the small or the large height the detail comes to the middle.
        withAnimation(.snappy) {
            detailID = item.id
            detent = SheetHeights.middle
        }
    }

    func openDetail(id: UUID) {
        if let item = trip.items.first(where: { $0.id == id }) { openDetail(item) }
    }

    /// Saves the time sheet; a plan that is not a stay and gets its first fixed time is asked 「予約が要る？」 once.
    func saveTime(_ item: ItineraryItem, duration: Int, fixed: Int?) {
        let first = item.fixedStartMinutes == nil && fixed != nil
        item.durationMinutes = duration
        item.fixedStartMinutes = fixed
        if first, item.kind != .stay, item.bookingNeeded == nil { bookingQuestion = item }
    }

    /// After the time sheet closes, 「予約が要る？」 for a plan that just got its first fixed time.
    func askBookingAfterTime() {
        askingBooking = bookingQuestion
        bookingQuestion = nil
    }
}

extension View {
    /// 「予約が要る？」, asked once after a plan that is not a stay first gets a fixed time (Notion 02 §6-3,
    /// 2026-10-27). The answer is kept, so it is not asked again.
    func bookingQuestion(_ item: Binding<ItineraryItem?>) -> some View {
        alert(
            "予約が要る？",
            isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
            presenting: item.wrappedValue
        ) { plan in
            Button("予約が要る") { plan.bookingNeeded = true }
            Button("要らない", role: .cancel) { plan.bookingNeeded = false }
        } message: { plan in
            Text("「\(plan.title)」を準備タブの予約に並べますか？")
        }
    }
}
