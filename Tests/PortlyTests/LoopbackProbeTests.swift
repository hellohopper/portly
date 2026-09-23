import Testing
import Foundation
@testable import PortlyCore

struct LoopbackProbeTests {

    /// Opens a loopback TCP listener on an ephemeral port; returns (fd, port).
    private func listenOnLoopback() -> (Int32, Int) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        listen(fd, 4)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        return (fd, Int(UInt16(bigEndian: address.sin_port)))
    }

    @Test func detectsAListeningPort() {
        let (fd, port) = listenOnLoopback()
        defer { close(fd) }
        #expect(LoopbackProbe.isAcceptingConnections(port: port))
    }

    @Test func reportsAClosedPortAsNotListening() {
        let (fd, port) = listenOnLoopback()
        close(fd)
        #expect(!LoopbackProbe.isAcceptingConnections(port: port))
    }

    @Test func rejectsOutOfRangePorts() {
        #expect(!LoopbackProbe.isAcceptingConnections(port: 0))
        #expect(!LoopbackProbe.isAcceptingConnections(port: 70_000))
    }
}
