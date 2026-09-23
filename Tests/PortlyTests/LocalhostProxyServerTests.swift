import Testing
import Foundation
@testable import PortlyCore

struct LocalhostProxyServerTests {

    // MARK: - hostHeader

    @Test func extractsHostHeaderCaseInsensitively() {
        let request = "GET / HTTP/1.1\r\nHost: myapp.localhost:7777\r\nAccept: */*\r\n\r\n"
        #expect(LocalhostProxyServer.hostHeader(from: request) == "myapp.localhost:7777")
    }

    @Test func hostHeaderLookupIsCaseInsensitiveOnTheKey() {
        let request = "GET / HTTP/1.1\r\nhOST: myapp.localhost\r\n\r\n"
        #expect(LocalhostProxyServer.hostHeader(from: request) == "myapp.localhost")
    }

    @Test func hostHeaderReturnsNilWhenAbsent() {
        let request = "GET / HTTP/1.1\r\nAccept: */*\r\n\r\n"
        #expect(LocalhostProxyServer.hostHeader(from: request) == nil)
    }

    // MARK: - proxyName(fromHost:)

    @Test func extractsNameFromBareLocalhostHost() {
        #expect(LocalhostProxyServer.proxyName(fromHost: "myapp.localhost") == "myapp")
    }

    @Test func extractsNameFromHostWithPort() {
        #expect(LocalhostProxyServer.proxyName(fromHost: "myapp.localhost:7777") == "myapp")
    }

    @Test func lowercasesTheExtractedName() {
        #expect(LocalhostProxyServer.proxyName(fromHost: "MyApp.LOCALHOST") == "myapp")
    }

    @Test func rejectsNonLocalhostHosts() {
        #expect(LocalhostProxyServer.proxyName(fromHost: "example.com") == nil)
        #expect(LocalhostProxyServer.proxyName(fromHost: "localhost") == nil)
        #expect(LocalhostProxyServer.proxyName(fromHost: ".localhost") == nil)
    }

    // MARK: - isValidName

    @Test func acceptsSimpleLowercaseNames() {
        #expect(LocalhostProxyServer.isValidName("myapp"))
        #expect(LocalhostProxyServer.isValidName("my-app-2"))
    }

    @Test func rejectsInvalidNames() {
        #expect(!LocalhostProxyServer.isValidName(""))
        #expect(!LocalhostProxyServer.isValidName("-myapp"))
        #expect(!LocalhostProxyServer.isValidName("myapp-"))
        #expect(!LocalhostProxyServer.isValidName("my app"))
        #expect(!LocalhostProxyServer.isValidName("MyApp"))
        #expect(!LocalhostProxyServer.isValidName("my.app"))
        #expect(!LocalhostProxyServer.isValidName(String(repeating: "a", count: 64)))
    }

    // MARK: - requestLine (keep-alive request logging)

    @Test func detectsARequestLineAtTheStartOfAChunk() {
        let chunk = Data("POST /api/users HTTP/1.1\r\nHost: app.localhost\r\n\r\n{}".utf8)
        #expect(LocalhostProxyServer.requestLine(startingChunk: chunk) == "POST /api/users HTTP/1.1")
    }

    @Test func ignoresBodyBytesAndNonHTTPTraffic() {
        #expect(LocalhostProxyServer.requestLine(startingChunk: Data("{\"a\": 1}\r\n".utf8)) == nil)
        #expect(LocalhostProxyServer.requestLine(startingChunk: Data("GET /no-version\r\n".utf8)) == nil)
        #expect(LocalhostProxyServer.requestLine(startingChunk: Data([0x16, 0x03, 0x01, 0x0d])) == nil)
    }
}
