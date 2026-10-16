import SwiftUI

/// One plan with its times in the left column (Notion 02 §6-5 時刻の見せ方, Figma 124:2).
/// Start on top, end below; a guess is light, a fixed time is dark with a lock. Tapping the times opens the time sheet.
struct ItineraryRow: View {
    let item: ItineraryItem
    let number: Int
    let color: Color
    let isHighlighted: Bool
    /// Nil in 未定, which has no times.
    let slot: DaySchedule.Slot?
    let onTapTime: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let slot {
                timeColumn(slot)
            }
            ItineraryCard(item: item, number: number, color: color, isHighlighted: isHighlighted)
        }
    }

    private func timeColumn(_ slot: DaySchedule.Slot) -> some View {
        Button(action: onTapTime) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 2) {
                    if slot.isFixed { Image(systemName: "lock.fill").font(.system(size: 8)) }
                    Text(DaySchedule.clock(slot.startMinutes))
                }
                .font(Theme.latin(12, slot.isFixed ? .bold : .medium))
                .foregroundStyle(slot.isFixed ? Theme.ink : Theme.secondary)
                Text(DaySchedule.clock(slot.endMinutes))
                    .font(Theme.latin(11, .medium))
                    .foregroundStyle(Theme.faint)
            }
            .frame(width: 46, alignment: .trailing)
            .padding(.top, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(DaySchedule.clock(slot.startMinutes))から\(DaySchedule.clock(slot.endMinutes))、時刻を変える")
    }
}
