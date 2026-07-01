import Testing
@testable import Porty

struct PortScannerTests {

    @Test func extractPortFromWildcardAddress() {
        #expect(PortScanner.extractPort(from: "*:5173") == 5173)
    }

    @Test func extractPortFromLoopbackAddress() {
        #expect(PortScanner.extractPort(from: "127.0.0.1:3000") == 3000)
    }

    @Test func extractPortFromIPv6Address() {
        #expect(PortScanner.extractPort(from: "[::1]:8080") == 8080)
    }

    @Test func extractPortFromConnectedSocket() {
        #expect(PortScanner.extractPort(from: "192.168.1.5:53->8.8.8.8:53") == 53)
    }

    @Test func extractPortReturnsNilForMalformedInput() {
        #expect(PortScanner.extractPort(from: "no-colon-here") == nil)
    }

    @Test func dedupeCollapsesSameProcessOnIPv4AndIPv6() {
        let entries = [
            PortInfo(pid: 100, port: 3000, proto: "TCP", processName: "node", commandPath: nil),
            PortInfo(pid: 100, port: 3000, proto: "TCP", processName: "node", commandPath: nil),
            PortInfo(pid: 200, port: 8080, proto: "TCP", processName: "python", commandPath: nil)
        ]

        #expect(PortScanner.dedupe(entries).count == 2)
    }

    @Test func dedupeKeepsDifferentProtocolsOnSamePortSeparate() {
        let entries = [
            PortInfo(pid: 100, port: 53, proto: "TCP", processName: "dnsd", commandPath: nil),
            PortInfo(pid: 100, port: 53, proto: "UDP", processName: "dnsd", commandPath: nil)
        ]

        #expect(PortScanner.dedupe(entries).count == 2)
    }

    @Test func mergeSamePidAndPortCombinesProtocols() {
        let entries = [
            PortInfo(pid: 100, port: 53, proto: "TCP", processName: "dnsd", commandPath: nil),
            PortInfo(pid: 100, port: 53, proto: "UDP", processName: "dnsd", commandPath: nil)
        ]

        let merged = PortScanner.mergeSamePidAndPort(entries)

        #expect(merged.count == 1)
        #expect(merged.first?.proto == "TCP+UDP")
    }

    @Test func mergeSamePidAndPortKeepsDifferentPidsOrPortsSeparate() {
        let entries = [
            PortInfo(pid: 100, port: 3000, proto: "TCP", processName: "node", commandPath: nil),
            PortInfo(pid: 200, port: 3000, proto: "TCP", processName: "python", commandPath: nil),
            PortInfo(pid: 100, port: 4000, proto: "TCP", processName: "node", commandPath: nil)
        ]

        #expect(PortScanner.mergeSamePidAndPort(entries).count == 3)
    }
}
