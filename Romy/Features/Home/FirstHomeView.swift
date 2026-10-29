import SwiftUI

/// Home when there is no trip yet: one line and the way in, no extra text (Notion 02 §6 ⓪).
struct FirstHomeView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("Let's Travel !!")
                .font(Theme.latin(34, .bold))
                .foregroundStyle(Theme.ink)
            Button(action: onStart) {
                Text("旅行を作る")
                    .font(Theme.jp(17, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(Theme.ink))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            Spacer()
            AttributionButton()
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface.ignoresSafeArea())
    }
}

#Preview {
    FirstHomeView {}
}
