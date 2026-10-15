import MapKit
import SwiftUI

/// The open 行き先 card: search, catalog results, Apple's area results, then the chosen chips.
/// Chips sit below the list so adding one does not move the rows under the finger.
struct DestinationSearchCard: View {
    @Bindable var model: TripCreationModel
    var focusedField: FocusState<TripCreationModel.Step?>.Binding

    @State private var query = ""
    @State private var areaSearch = AreaSearch()

    private let catalog = DestinationCatalog.bundled

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("どこへ行く？").font(Theme.jp(24, .bold)).foregroundStyle(Theme.ink)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                TextField("都道府県・市区町村・観光地", text: $query)
                    .font(Theme.jp(15))
                    .focused(focusedField, equals: .destinations)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faint)
                    }
                    .accessibilityLabel("検索を消す")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.fill))

            let catalogResults = catalog.search(query)
            let catalogNames = Set(catalogResults.map(\.name))
            let apple = areaSearch.results.filter { !catalogNames.contains($0.title) }

            if !catalogResults.isEmpty || !apple.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(catalogResults) { destination in
                        resultRow(title: destination.name, subtitle: destination.detail,
                                  isSelected: model.destinations.contains { $0.id == destination.id }) {
                            withAnimation(.snappy) { model.toggle(destination) }
                        }
                    }
                    ForEach(apple, id: \.self) { result in
                        resultRow(title: result.title, subtitle: chosen(result)?.detail ?? result.detail,
                                  isSelected: chosen(result) != nil) {
                            Task { await choose(result) }
                        }
                    }
                }
            }

            if !model.destinations.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(model.destinations) { destination in
                        Button { withAnimation(.snappy) { model.toggle(destination) } } label: {
                            HStack(spacing: 6) {
                                Text(destination.name).font(Theme.jp(14, .bold))
                                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Theme.ink))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(destination.name)を外す")
                    }
                }
            }
        }
        .onChange(of: query) { _, newValue in areaSearch.update(query: newValue) }
    }

    private func chosen(_ result: AreaSearch.Result) -> Destination? {
        model.destinations.first { $0.kind == result.kind && $0.name == result.title }
    }

    private func resultRow(
        title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.jp(15, .bold)).foregroundStyle(Theme.ink)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(Theme.jp(12)).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ result: AreaSearch.Result) async {
        if let existing = chosen(result) {
            withAnimation(.snappy) { model.toggle(existing) }
            return
        }
        guard let destination = await areaSearch.destination(for: result) else { return }
        withAnimation(.snappy) { model.toggle(destination) }
    }
}
