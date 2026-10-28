import SwiftUI

/// A line a stay adds to another day (Notion 02 §6-5 合意 2026-10-10, 決定 2026-10-28, Figma 宿A・A2 3日目 案1):
/// 「ホテルを出る」 first on the day it is left, with the day's start in the left column (when the person plans to
/// leave) and the check-out on the right; 「ホテル名 ・ 2泊目」 small at the end of a middle day. They come from
/// the stay, so they cannot be moved or deleted; tapping one opens the stay.
struct StayLineRow: View {
    let line: StayLine
    /// The day's start, shown for 「ホテルを出る」; nil in 未定.
    let startMinutes: Int?
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: TimeLineLayout.rowSpacing) {
            Text(line.kind == .leaving ? startMinutes.map { DaySchedule.clock($0) } ?? "" : "")
                .font(Theme.latin(12, .medium))
                .foregroundStyle(Theme.secondary)
                .frame(width: TimeLineLayout.timeWidth, alignment: .trailing)
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Image(systemName: "bed.double")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                    Text(line.kind == .leaving ? "ホテルを出る" : line.stay.title)
                        .font(Theme.jp(14, .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let note = line.note {
                        Text(note).font(Theme.jp(12, .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.fill))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityText)
        }
    }

    private var accessibilityText: String {
        switch line.kind {
        case .leaving: "\(line.stay.title)を出る。\(line.note ?? "")"
        case .night(let number): "\(line.stay.title)、\(number)泊目"
        }
    }
}
