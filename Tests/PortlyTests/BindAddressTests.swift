import Testing
@testable import PortlyCore

struct BindAddressTests {

    @Test func extractsAddressAndPort() {
        #expect(PortScanner.extractEndpoint(from: "127.0.0.1:3000")?.address == "127.0.0.1")
        #expect(PortScanner.extractEndpoint(from: "127.0.0.1:3000")?.port == 3000)
        #expect(PortScanner.extractEndpoint(from: "*:5173")?.address == "*")
    }

    @Test func unwrapsIPv6Literals() {
        #expect(PortScanner.extractEndpoint(from: "[::1]:8080")?.address == "::1")
        #expect(PortScanner.extractEndpoint(from: "[::1]:8080")?.port == 8080)
    }

    @Test func flagsWildcardBindsAsExposed() {
        for address in ["*", "0.0.0.0", "::"] {
            var info = PortInfo(pid: 1, port: 3000, proto: "TCP", processName: "node", commandPath: nil)
            info.bindAddress = address
            #expect(info.isExposedToNetwork, "\(address) should count as exposed")
        }
    }

    @Test func loopbackIsNotExposed() {
        for address in ["127.0.0.1", "::1"] {
            var info = PortInfo(pid: 1, port: 3000, proto: "TCP", processName: "node", commandPath: nil)
            info.bindAddress = address
            #expect(!info.isExposedToNetwork)
        }
    }

    @Test func unknownBindAddressIsNotAssumedExposed() {
        let info = PortInfo(pid: 1, port: 3000, proto: "TCP", processName: "node", commandPath: nil)
        #expect(!info.isExposedToNetwork)
    }

    /// A process bound to both loopback and the wildcard is reachable from the
    /// network; dedupe must not let the loopback row win just by coming first.
    @Test func dedupeKeepsTheExposedBind() {
        var loopback = PortInfo(pid: 1, port: 3000, proto: "TCP", processName: "node", commandPath: nil)
        loopback.bindAddress = "127.0.0.1"
        var wildcard = PortInfo(pid: 1, port: 3000, proto: "TCP", processName: "node", commandPath: nil)
        wildcard.bindAddress = "*"

        let result = PortScanner.dedupe([loopback, wildcard])
        #expect(result.count == 1)
        #expect(result[0].isExposedToNetwork)
    }

    @Test func exposedPortsAreSearchable() {
        var info = PortInfo(pid: 1, port: 3000, proto: "TCP", processName: "node", commandPath: nil)
        info.bindAddress = "0.0.0.0"
        #expect(info.matches(query: "exposed"))
    }
}
