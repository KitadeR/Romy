import SwiftUI

/// Available before creating a trip and from the trip list.
struct AttributionButton: View {
    @State private var isPresented = false

    var body: some View {
        Button("出典・ライセンス", systemImage: "info.circle") {
            isPresented = true
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(minHeight: 44)
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                AttributionsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる", systemImage: "xmark") { isPresented = false }
                        }
                    }
            }
            .presentationDetents([.large])
        }
    }
}
