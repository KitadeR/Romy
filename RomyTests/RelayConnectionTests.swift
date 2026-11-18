import Foundation
import Testing
@testable import Romy

struct RelayConnectionTests {
    private let published = RelayConfig(url: URL(string: "https://relay.example.com")!, token: "test-app-token")

    @Test(arguments: [true, false])
    func ordinaryRunsUseThePublishedRelay(allowsLocal: Bool) {
        let relay = FactRelay.configured(published: published, arguments: [], allowsLocal: allowsLocal)
        #expect(relay.baseURL == published.url)
        #expect(relay.token == published.token)
    }

    @Test(arguments: [true, false])
    func missingPublishedSettingsDoNotSilentlyUseLocalhost(allowsLocal: Bool) {
        let relay = FactRelay.configured(published: nil, arguments: [], allowsLocal: allowsLocal)
        #expect(relay.baseURL == nil)
        #expect(relay.token == nil)
    }

    @Test func explicitLocalDevelopmentNeverForwardsThePublishedToken() {
        let relay = FactRelay.configured(published: published, arguments: [FactRelay.localArgument], allowsLocal: true)
        #expect(relay.baseURL == URL(string: "http://localhost:8787"))
        #expect(relay.token == nil)
    }

    @Test func localDevelopmentWorksWithoutPublishedSettings() {
        let relay = FactRelay.configured(published: nil, arguments: [FactRelay.localArgument], allowsLocal: true)
        #expect(relay.baseURL == URL(string: "http://localhost:8787"))
        #expect(relay.token == nil)
    }

    @Test func devicesAndReleaseBuildsIgnoreTheLocalArgument() {
        let relay = FactRelay.configured(published: published, arguments: [FactRelay.localArgument], allowsLocal: false)
        #expect(relay.baseURL == published.url)
        #expect(relay.token == published.token)
    }

    @Test func anIgnoredLocalArgumentDoesNotEnableChecksWithoutPublishedSettings() {
        let relay = FactRelay.configured(published: nil, arguments: [FactRelay.localArgument], allowsLocal: false)
        #expect(relay.baseURL == nil)
        #expect(relay.token == nil)
    }

    @Test func theSharedClientReadsTheConfigurationFromTheAppBundle() {
        let config = Bundle.main.url(forResource: "Relay", withExtension: "plist")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap(RelayConfig.decode)
        // Keep real connection settings and tokens out of assertion failure output.
        let matchesPublished = FactRelay.shared.baseURL == config?.url && FactRelay.shared.token == config?.token
        #expect(matchesPublished)
    }
}
