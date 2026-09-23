import Testing
import Foundation
@testable import PortlyCore

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

    @Test func extractPortReturnsNilForUnboundUDPSocket() {
        // lsof reports fully-unbound UDP sockets as "*:*".
        #expect(PortScanner.extractPort(from: "*:*") == nil)
    }

    @Test func mergeIsIdempotentAcrossRepeatedProtocols() {
        // A pid+port pair appearing more than twice must not grow "TCP+UDP+UDP".
        let entries = [
            PortInfo(pid: 100, port: 53, proto: "TCP", processName: "dnsd", commandPath: nil),
            PortInfo(pid: 100, port: 53, proto: "UDP", processName: "dnsd", commandPath: nil),
            PortInfo(pid: 100, port: 53, proto: "UDP", processName: "dnsd", commandPath: nil)
        ]

        let merged = PortScanner.mergeSamePidAndPort(entries)

        #expect(merged.count == 1)
        #expect(merged.first?.proto == "TCP+UDP")
    }

    @Test func mergePreservesFirstSeenOrder() {
        let entries = [
            PortInfo(pid: 100, port: 8000, proto: "TCP", processName: "python", commandPath: nil),
            PortInfo(pid: 200, port: 3000, proto: "TCP", processName: "node", commandPath: nil),
            PortInfo(pid: 100, port: 8000, proto: "UDP", processName: "python", commandPath: nil)
        ]

        #expect(PortScanner.mergeSamePidAndPort(entries).map(\.port) == [8000, 3000])
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

    // MARK: - Native (libproc) scanning

    /// A real listener this process opens is reported with the right pid, port,
    /// protocol and bind address -- the fields lsof used to provide.
    @Test func nativeScanFindsOwnTCPListener() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #expect(fd >= 0)
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        #expect(bound == 0)
        #expect(listen(fd, 1) == 0)

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        let port = Int(UInt16(bigEndian: address.sin_port))

        let entries = try #require(NativeSocketScanner.scan())
        let mine = try #require(entries.first {
            $0.pid == ProcessInfo.processInfo.processIdentifier && $0.port == port
        })
        #expect(mine.proto == "TCP")
        #expect(mine.bindAddress == "127.0.0.1")
        #expect(!mine.isExposedToNetwork)
    }
}
