import SwiftUI

struct AttributionArticlesView: View {
    @State private var articles: [AttributionArticle] = []
    @State private var query = ""
    @State private var isLoaded = false
    @State private var failed = false

    private var matching: [AttributionArticle] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return articles }
        return articles.filter { $0.title.localizedStandardContains(term) || $0.id.localizedStandardContains(term) }
    }

    var body: some View {
        Group {
            if failed {
                ContentUnavailableView("一覧を読み込めませんでした", systemImage: "doc.text")
            } else if !isLoaded {
                ProgressView("一覧を読み込み中")
            } else {
                List {
                    Section {
                        Text("観光地データの作成時に参照した元記事の索引です。すべての記事から読みを取得したという意味ではありません。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("元記事（\(matching.count)件）") {
                        ForEach(matching) { article in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(article.title).font(.headline)
                                Link("Wikipediaの元記事", destination: article.wikipediaURL)
                                    .accessibilityLabel("\(article.title)のWikipedia記事を開く")
                                Link("Wikidataの項目（\(article.id)）", destination: article.wikidataURL)
                                    .accessibilityLabel("\(article.title)のWikidata項目を開く")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .overlay {
                    if matching.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
        }
        .navigationTitle("観光地データの元記事")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "記事名・Wikidata IDで検索")
        .task { load() }
    }

    private func load() {
        do {
            articles = try AttributionResources.articles()
            isLoaded = true
        } catch {
            failed = true
        }
    }
}
