import SwiftUI

/// The place of a stay decided later, once it is decided (Notion 02 §6-5 2026-10-28): the same search as
/// 「宿を追加」 — a hotel by name, the others by address.
struct StayPlacePicker: View {
    let kind: StayKind
    let trip: Trip?
    let onPick: (PlaceSearch.Result) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var search = PlaceSearch()
    @State private var resolvingID: String?
    @FocusState private var isTyping: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("宿の場所").font(Theme.jp(22, .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.fill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("閉じる")
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                TextField(kind == .hotel ? "ホテルの名前" : "住所", text: $query)
                    .font(Theme.jp(15, .medium))
                    .focused($isTyping)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.fill))
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(search.results) { result in
                        Button { pick(result) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.title).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                                Text(result.detail).font(Theme.jp(12, .medium)).foregroundStyle(Theme.secondary)
                                    .lineLimit(1)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
                            .opacity(resolvingID == result.id ? 0.5 : 1)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .background(Theme.surface.ignoresSafeArea())
        .task { await search.prepare(for: trip?.destinations ?? []) }
        .onChange(of: query) { _, newValue in search.update(query: newValue) }
        .onAppear { isTyping = true }
    }

    private func pick(_ result: PlaceSearch.Result) {
        guard resolvingID == nil else { return }
        guard result.item == nil else {
            onPick(result)
            dismiss()
            return
        }
        resolvingID = result.id
        Task {
            let resolved = await PlaceSearch.resolve(result)
            resolvingID = nil
            if let resolved {
                onPick(resolved)
                dismiss()
            }
        }
    }
}
