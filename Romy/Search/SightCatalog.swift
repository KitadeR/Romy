import Foundation

/// Famous sights in Japan, bundled as sights.json and built by Tools/sights/build_sights.py
/// (Issue #2): Wikidata (CC0) for the places, Japanese Wikipedia pageviews for fame,
/// and readings from Wikidata, the Wikipedia intro or a macOS guess.
struct SightCatalog {
    struct Entry: Decodable {
        let id: String
        let name: String
        let aliases: [String]
        /// Readings of the official name.
        let kana: [String]
        /// Guessed reading of each alias, same order as `aliases`.
        let aliasKana: [String]
        let kind: String
        let town: String?
        let prefecture: String?
        let lat: Double
        let lon: Double
        let views: Int
    }

    let entries: [Entry]
    /// Folded official name and aliases, prepared once (folding uses ICU transforms).
    private let folded: [(name: String, aliases: [String])]

    init(entries: [Entry]) {
        self.entries = entries
        self.folded = entries.map { (Self.fold($0.name), $0.aliases.map(Self.fold)) }
    }

    static let bundled: SightCatalog = {
        guard let url = Bundle.main.url(forResource: "sights", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return SightCatalog(entries: [])
        }
        return SightCatalog(entries: entries)
    }()

    /// Matches the official name, an alias (「金閣寺」 for 鹿苑寺) or their readings.
    /// Order: official name starts with the text → official name contains it → an alias starts with it →
    /// an alias contains it; the more viewed first within each. An alias match shows the alias.
    func search(_ query: String, limit: Int = 5) -> [Destination] {
        let text = Self.fold(query)
        guard !text.isEmpty else { return [] }
        var hits: [Hit] = []
        for (entry, names) in zip(entries, folded) {
            let official = [names.name] + entry.kana
            if official.contains(where: { $0.hasPrefix(text) }) {
                hits.append(Hit(entry: entry, shown: entry.name, rank: 0))
            } else if official.contains(where: { $0.contains(text) }) {
                hits.append(Hit(entry: entry, shown: entry.name, rank: 1))
            } else if let index = aliasIndex(entry, names.aliases, where: { $0.hasPrefix(text) }) {
                hits.append(Hit(entry: entry, shown: entry.aliases[index], rank: 2))
            } else if let index = aliasIndex(entry, names.aliases, where: { $0.contains(text) }) {
                hits.append(Hit(entry: entry, shown: entry.aliases[index], rank: 3))
            }
        }
        return hits
            .sorted { ($0.rank, -$0.entry.views) < ($1.rank, -$1.entry.views) }
            .prefix(limit)
            .map { Self.destination($0.entry, shownName: $0.shown) }
    }

    private func aliasIndex(_ entry: Entry, _ aliases: [String], where match: (String) -> Bool) -> Int? {
        aliases.indices.first { index in
            match(aliases[index]) || (entry.aliasKana.indices.contains(index) && match(entry.aliasKana[index]))
        }
    }

    private struct Hit {
        let entry: Entry
        let shown: String
        /// 0–3, see `search`.
        let rank: Int
    }

    /// 「北区」 alone is ambiguous, so wards outside Tokyo get the prefecture: 「北区（京都府）」.
    static func place(town: String?, prefecture: String?) -> String? {
        guard let town else { return prefecture }
        if town.hasSuffix("区"), let prefecture, prefecture != "東京都" {
            return "\(town)（\(prefecture)）"
        }
        return town
    }

    private static func destination(_ entry: Entry, shownName: String) -> Destination {
        Destination(
            id: "sight:\(entry.id)",
            name: shownName,
            context: place(town: entry.town, prefecture: entry.prefecture),
            kind: .landmark,
            category: entry.kind,
            latitude: entry.lat,
            longitude: entry.lon
        )
    }

    /// Hiragana, full-width letters, lower case, no spaces or middle dots.
    /// (Half-width would also turn katakana half-width, so everything goes full-width.)
    nonisolated static func fold(_ text: String) -> String {
        let wide = text.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? text
        let kana = wide.applyingTransform(.hiraganaToKatakana, reverse: true) ?? wide
        return kana.lowercased().filter { !" 　・･".contains($0) }
    }
}
