import Foundation

/// Prefectures and municipalities from the MIC list of local government codes
/// (総務省「全国地方公共団体コード」, as of 2024-01-01), bundled as municipalities.json.
/// Source: https://www.soumu.go.jp/denshijiti/code.html
struct DestinationCatalog {
    struct Entry: Decodable {
        let code: String
        let prefecture: String
        let name: String
        let kana: String
        let isPrefecture: Bool

        var destination: Destination {
            Destination(
                id: code,
                name: name,
                context: isPrefecture ? nil : prefecture,
                kind: isPrefecture ? .prefecture : .municipality
            )
        }
    }

    let entries: [Entry]

    static let bundled: DestinationCatalog = {
        guard let url = Bundle.main.url(forResource: "municipalities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return DestinationCatalog(entries: [])
        }
        return DestinationCatalog(entries: entries)
    }()

    /// Matches the name or its hiragana reading. Prefix matches first, prefectures before municipalities.
    func search(_ query: String, limit: Int = 20) -> [Destination] {
        let text = Self.normalize(query)
        guard !text.isEmpty else { return [] }
        var prefix: [Entry] = []
        var contains: [Entry] = []
        for entry in entries {
            if entry.name.hasPrefix(text) || entry.kana.hasPrefix(text) {
                prefix.append(entry)
            } else if entry.name.contains(text) || entry.kana.contains(text) {
                contains.append(entry)
            }
        }
        let ordered = prefix.filter(\.isPrefecture) + prefix.filter { !$0.isPrefecture } + contains
        return ordered.prefix(limit).map(\.destination)
    }

    /// Trims spaces and turns katakana into hiragana so 「キョウト」 finds 「きょうと」.
    static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.applyingTransform(.hiraganaToKatakana, reverse: true) ?? trimmed
    }
}
