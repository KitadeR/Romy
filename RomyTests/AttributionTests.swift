import Foundation
import Testing
@testable import Romy

@MainActor
struct AttributionTests {
    private let header = "wikidata_id,wikipedia_title,wikipedia_url,wikidata_url\n"

    @Test func quotedArticleNamesAndCRLFArePreserved() throws {
        let row = "Q1,\"地名, \"\"別名\"\"\n公園\",https://ja.wikipedia.org/wiki/Example,https://www.wikidata.org/wiki/Q1\r\n"
        let articles = try AttributionResources.parseArticles(header + row)
        #expect(articles.count == 1)
        #expect(articles.first?.title == "地名, \"別名\"\n公園")
    }

    @Test func malformedOrUnexpectedLinksAreRejected() {
        for row in [
            "Q1,公園,https://example.com/wiki/Test,https://www.wikidata.org/wiki/Q1",
            "Q1,公園,https://ja.wikipedia.org/wiki/Test,https://www.wikidata.org/wiki/Q2",
            "Q1,\"閉じない,https://ja.wikipedia.org/wiki/Test,https://www.wikidata.org/wiki/Q1"
        ] {
            #expect(throws: (any Error).self) {
                try AttributionResources.parseArticles(header + row)
            }
        }
    }

    @Test func bundledAttributionsContainBothFullFontLicensesAndAllArticles() throws {
        let notice = try AttributionResources.notice()
        for name in ["OFL-ZenKakuGothicNew", "OFL-PlusJakartaSans"] {
            let url = try #require(Bundle.main.url(forResource: name, withExtension: "txt"))
            let original = try String(contentsOf: url, encoding: .utf8)
            #expect(notice.contains(original))
        }
        let articles = try AttributionResources.articles()
        #expect(articles.count == 2500)
        #expect(Set(articles.map(\.id)).count == 2500)
        #expect(articles.contains { $0.title == "清水寺" })
    }
}
