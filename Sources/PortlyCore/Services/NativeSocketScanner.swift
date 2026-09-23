import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Lists listening sockets straight from the kernel via libproc -- the same data
/// `lsof -iTCP -sTCP:LISTEN -iUDP` prints, without spawning it and parsing its text.
/// lsof was the most expensive part of every refresh, and it runs every 2s while the
/// panel is open.
///
/// Visibility matches unprivileged lsof exactly (which uses the same calls):
/// sockets of processes owned by other users (root daemons) can't be read.
enum NativeSocketScanner {

    /// nil when the process list itself couldn't be read, so the caller can fall
    /// back to lsof; an empty array is a legitimate "nothing is listening".
    static func scan() -> [PortInfo]? {
        guard let pids = allPids() else { return nil }
        var entries: [PortInfo] = []
        for pid in pids where pid > 0 {
            entries.append(contentsOf: listeningSockets(of: pid))
        }
        return entries
    }

    private static func allPids() -> [pid_t]? {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return nil }
        // Headroom for processes spawned between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(needed) / MemoryLayout<pid_t>.stride + 64)
        let written = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard written > 0 else { return nil }
        return Array(pids.prefix(Int(written) / MemoryLayout<pid_t>.stride))
    }

    private static func listeningSockets(of pid: pid_t) -> [PortInfo] {
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        // Fails (0) for other users' processes; nothing to report, same as lsof.
        guard needed > 0 else { return [] }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / MemoryLayout<proc_fdinfo>.stride + 16)
        let written = fds.withUnsafeMutableBytes { buffer in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard written > 0 else { return [] }
        let count = Int(written) / MemoryLayout<proc_fdinfo>.stride

        var result: [PortInfo] = []
        var name: String?
        for fd in fds.prefix(count) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            guard let socket = listeningEndpoint(pid: pid, fd: fd.proc_fd) else { continue }
            if name == nil { name = processName(of: pid) }
            result.append(PortInfo(
                pid: pid,
                port: socket.port,
                proto: socket.proto,
                processName: name ?? "",
                commandPath: nil,
                bindAddress: socket.address
            ))
        }
        return result
    }

    private static func listeningEndpoint(pid: pid_t, fd: Int32) -> (proto: String, port: Int, address: String)? {
        var info = socket_fdinfo()
        let size = Int32(MemoryLayout<socket_fdinfo>.size)
        guard proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &info, size) == size else { return nil }

        let socket = info.psi
        guard socket.soi_family == AF_INET || socket.soi_family == AF_INET6 else { return nil }

        let endpoint: in_sockinfo
        let proto: String
        switch Int(socket.soi_kind) {
        case SOCKINFO_TCP:
            guard socket.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { return nil }
            endpoint = socket.soi_proto.pri_tcp.tcpsi_ini
            proto = "TCP"
        case SOCKINFO_IN where socket.soi_protocol == IPPROTO_UDP:
            endpoint = socket.soi_proto.pri_in
            // A connected UDP socket (non-zero remote port) is a client, e.g. a
            // browser's QUIC connection -- not something listening for others.
            guard endpoint.insi_fport == 0 else { return nil }
            proto = "UDP"
        default:
            return nil
        }

        let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: endpoint.insi_lport)))
        guard port > 0 else { return nil }
        return (proto, port, address(of: endpoint))
    }

    /// Formatted like lsof: "*" for the wildcard address, bare IPv6 without brackets.
    private static func address(of endpoint: in_sockinfo) -> String {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        if endpoint.insi_vflag & UInt8(INI_IPV4) != 0 {
            var address = endpoint.insi_laddr.ina_46.i46a_addr4
            if address.s_addr == 0 { return "*" }
            inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count))
        } else {
            var address = endpoint.insi_laddr.ina_6
            if withUnsafeBytes(of: &address, { $0.allSatisfy { $0 == 0 } }) { return "*" }
            inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count))
        }
        return decodeCString(buffer)
    }

    /// The same name lsof's `c` field reports: the kernel's full process name,
    /// falling back to the (16-char) comm.
    private static func processName(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? decodeCString(buffer) : ""
    }

    /// A NUL-terminated C buffer as a String.
    static func decodeCString(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
