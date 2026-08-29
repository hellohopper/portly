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

    /// Both protocols now come from a single lsof call, tagged by the `P` field.
    @Test func parsesProtocolFromTheFieldOutput() {
        let output = """
        p983
        crapportd
        f13
        PTCP
        n*:61512
        p1002
        cidentityservicesd
        f13
        PUDP
        n127.0.0.1:5353
        """
        let entries = PortScanner.parse(output)
        #expect(entries.count == 2)
        #expect(entries[0].proto == "TCP")
        #expect(entries[0].port == 61512)
        #expect(entries[0].processName == "rapportd")
        #expect(entries[1].proto == "UDP")
        #expect(entries[1].port == 5353)
        #expect(!entries[1].isExposedToNetwork)
    }

    @Test func skipsSocketsWithNoResolvablePort() {
        // Unbound UDP sockets report "*:*".
        let output = "p1\nca\nf1\nPUDP\nn*:*\n"
        #expect(PortScanner.parse(output).isEmpty)
    }

    @Test func exposedPortsAreSearchable() {
        var info = PortInfo(pid: 1, port: 3000, proto: "TCP", processName: "node", commandPath: nil)
        info.bindAddress = "0.0.0.0"
        #expect(info.matches(query: "exposed"))
    }
}
