import Testing
@testable import Portly

struct TunnelManagerTests {

    @Test func extractsURLFromCloudflaredBanner() {
        let banner = """
        +--------------------------------------------------------------------------------------------+
        |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):    |
        |  https://random-words-1234.trycloudflare.com                                                 |
        +--------------------------------------------------------------------------------------------+
        """
        #expect(TunnelManager.extractURL(from: banner) == "https://random-words-1234.trycloudflare.com")
    }

    @Test func returnsNilWhenNoURLIsPresentYet() {
        #expect(TunnelManager.extractURL(from: "INF Starting tunnel connection") == nil)
    }

    @Test func ignoresNonTrycloudflareURLs() {
        #expect(TunnelManager.extractURL(from: "Visit https://example.com for docs") == nil)
    }
}
