import SwiftUI

/// The dashed box of an empty day (Notion 02 §6-6, 案A): one tap opens adding.
struct DashedAddBox: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(Theme.jp(14, .bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.faint, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
