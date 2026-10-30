import Foundation

/// Reads only bundled files. Opening an external article is an explicit Link in the view.
enum AttributionResources {
    enum ReadError: Error {
        case missingResource, invalidCSV
    }

    static func notice(bundle: Bundle = .main) throws -> String {
        try read("RomyAttributions", extension: "txt", bundle: bundle)
    }

    static func articles(bundle: Bundle = .main) throws -> [AttributionArticle] {
        try parseArticles(read("RomySourceArticles", extension: "csv", bundle: bundle))
    }

    private static func read(_ name: String, extension suffix: String, bundle: Bundle) throws -> String {
        guard let url = bundle.url(forResource: name, withExtension: suffix) else {
            throw ReadError.missingResource
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func parseArticles(_ csv: String) throws -> [AttributionArticle] {
        let rows = try csvRows(csv)
        guard rows.first == ["wikidata_id", "wikipedia_title", "wikipedia_url", "wikidata_url"] else {
            throw ReadError.invalidCSV
        }
        var seen: Set<String> = []
        return try rows.dropFirst().map { fields in
            guard fields.count == 4, fields[0].hasPrefix("Q"), !fields[1].isEmpty,
                  seen.insert(fields[0]).inserted,
                  let wikipedia = URL(string: fields[2]), wikipedia.scheme == "https",
                  wikipedia.host == "ja.wikipedia.org", wikipedia.path.hasPrefix("/wiki/"),
                  let wikidata = URL(string: fields[3]), wikidata.scheme == "https",
                  wikidata.host == "www.wikidata.org", wikidata.path == "/wiki/\(fields[0])" else {
                throw ReadError.invalidCSV
            }
            return AttributionArticle(
                id: fields[0], title: fields[1], wikipediaURL: wikipedia, wikidataURL: wikidata
            )
        }
    }

    /// CSV fields can contain commas, doubled quotes, and line breaks inside quoted article names.
    private static func csvRows(_ csv: String) throws -> [[String]] {
        let characters = Array(csv)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var closedQuote = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        quoted = false
                        closedQuote = true
                    }
                } else {
                    field.append(character)
                }
            } else if character == "," {
                row.append(field)
                field = ""
                closedQuote = false
            } else if character == "\n" || character == "\r\n" || character == "\r" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                closedQuote = false
            } else if character == "\"", field.isEmpty, !closedQuote {
                quoted = true
            } else {
                guard !closedQuote, character != "\"" else { throw ReadError.invalidCSV }
                field.append(character)
            }
            index += 1
        }
        guard !quoted else { throw ReadError.invalidCSV }
        if !row.isEmpty || !field.isEmpty || closedQuote {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
