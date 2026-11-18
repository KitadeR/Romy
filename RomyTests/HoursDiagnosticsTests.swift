import Foundation
import Testing
@testable import Romy

@MainActor
struct HoursDiagnosticsTests {
    @Test(arguments: [
        "{\"reason\":\"error\"}",
        "{\"reason\":\"limit\",\"diagnostic\":{\"code\":\"session_limit\"}}",
        "{\"reason\":\"error\",\"diagnostic\":{\"code\":\"future_server_code\"}}"
    ])
    func oldAndNewRelayRepliesRemainReadable(json: String) throws {
        let reply = try JSONDecoder().decode(SceneAIReply.self, from: Data(json.utf8))
        #expect(reply.hours == nil)
        #expect(reply.reason != nil)
        if let code = reply.diagnostic?.code {
            let diagnostic = HoursDiagnostics.Code(rawValue: code) ?? .unknown
            #expect(diagnostic == (code == "session_limit" ? .sessionLimit : .unknown))
        }
    }
}
