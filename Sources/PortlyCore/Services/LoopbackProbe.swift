import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// "Is something accepting TCP connections on this port?" by just trying to connect
/// over loopback. A refused loopback connect fails immediately, so this costs a
/// couple of syscalls -- versus a full socket-table scan for the same answer.
public enum LoopbackProbe {

    public static func isAcceptingConnections(port: Int) -> Bool {
        guard (1...65535).contains(port) else { return false }
        return connects(family: AF_INET, port: UInt16(port)) || connects(family: AF_INET6, port: UInt16(port))
    }

    private static func connects(family: Int32, port: UInt16) -> Bool {
        let fd = socket(family, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        if family == AF_INET {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            return withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
        }

        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = port.bigEndian
        address.sin6_addr = in6addr_loopback
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
            }
        }
    }
}
