import MapKit
import SwiftUI

/// 位置情報を利用できないときの出発地。選んだ座標だけを徒歩検索に使う。
struct SceneOriginPicker: View {
    let onPick: (ProposalPlace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var search = PlaceSearch()
    @State private var resolving = false
    @State private var selection: PlaceSearch.Result?
    @State private var failed = false
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("施設名・駅名・住所", text: $query)
                    .textFieldStyle(.roundedBorder).focused($typing)
                    .onChange(of: query) { _, value in search.update(query: value) }
                if failed { Text("場所を確認できませんでした。別の候補をお選びください。") }
                if resolving { ProgressView("場所を確認中") }
                List(search.results) { result in
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        selection = result
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title).foregroundStyle(Theme.ink)
                            Text(result.detail).font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }.disabled(resolving)
                }.listStyle(.plain)
            }.padding(20)
                .background(Theme.surface)
                .navigationTitle("出発する場所").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                    }
                }
                .onAppear { typing = true }
                .task(id: selection?.id) {
                    if let selection { await pick(selection) }
                }
        }
    }

    private func pick(_ result: PlaceSearch.Result) async {
        resolving = true; failed = false
        defer { resolving = false }
        let resolved = result.item != nil ? result : await PlaceSearch.resolve(result)
        guard !Task.isCancelled else { return }
        guard let result = resolved, let item = result.item else { failed = true; return }
        onPick(ProposalPlace(name: result.title, latitude: item.location.coordinate.latitude,
                             longitude: item.location.coordinate.longitude))
        dismiss()
    }
}
