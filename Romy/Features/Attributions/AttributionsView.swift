import SwiftUI

struct AttributionsView: View {
    @State private var notice: String?
    @State private var failed = false

    var body: some View {
        Group {
            if let notice {
                List {
                    Section {
                        NavigationLink {
                            AttributionArticlesView()
                        } label: {
                            Label("観光地データの元記事", systemImage: "books.vertical")
                        }
                    } footer: {
                        Text("一覧とライセンス本文はオフラインでも閲覧できます。元サイトを開くには通信が必要です。")
                    }
                    Section("出典と利用条件") {
                        // Stable paragraphs of an immutable bundled notice; each can be read separately.
                        ForEach(
                            Array(notice.components(separatedBy: "\n\n").enumerated()), id: \.offset
                        ) { _, paragraph in
                            Text(verbatim: paragraph)
                                .font(.body)
                                .textSelection(.enabled)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            } else if failed {
                ContentUnavailableView(
                    "出典を読み込めませんでした",
                    systemImage: "doc.text",
                    description: Text("アプリを開き直して、もう一度お試しください。")
                )
            } else {
                ProgressView("出典を読み込み中")
            }
        }
        .navigationTitle("出典・ライセンス")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func load() {
        do {
            notice = try AttributionResources.notice()
        } catch {
            failed = true
        }
    }
}
