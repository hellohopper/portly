import Foundation

/// Who is actually talking to a port right now.
///
/// Answers the two questions the throughput number only hints at: is anything
/// actually hitting this server, and which of my services is calling which.
/// Deliberately on-demand -- this runs its own `lsof` and must never join the
/// 2-second poll.
public enum ConnectionResolver {

    public struct Peer: Identifiable, Sendable, Equatable {
        public let address: String
        /// The peer's process name, when the peer is local and resolvable.
        public let processName: String?
        public let count: Int

        public var id: String { address + (processName ?? "") }

        public var displayName: String {
            guard let processName else { return address }
            return count > 1 ? "\(processName) ×\(count)" : processName
        }
    }

    public static func peers(forPort port: Int, processTable: [Int32: (ppid: Int32, name: String)]) -> [Peer] {
        guard let output = Shell.run(
            "/usr/sbin/lsof",
            ["-nPw", "-iTCP:\(port)", "-sTCP:ESTABLISHED", "-F", "pcn"]
        ) else { return [] }
        return parse(output, port: port)
    }

    /// Groups established connections by their remote end. The listening process's own
    /// accepted sockets and the client side of the same connection both appear in
    /// lsof's output, so entries are keyed by the peer address.
    static func parse(_ output: String, port: Int) -> [Peer] {
        var currentCommand = ""
        var counts: [String: (name: String?, count: Int)] = [:]

        for rawLine in output.split(separator: "\n") {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())

            switch tag {
            case "c":
                currentCommand = value
            case "n":
                guard let arrow = value.range(of: "->") else { continue }
                let local = String(value[value.startIndex..<arrow.lowerBound])
                let remote = String(value[arrow.upperBound...])

                // Two rows describe each connection: the server's accepted socket
                // (local side is our port) and the client's (remote side is our port).
                // Count the *other* end in each case, naming it from whichever row
                // belongs to the client.
                let localIsOurs = local.hasSuffix(":\(port)")
                let peerAddress = localIsOurs ? remote : local
                let peerName = localIsOurs ? nil : currentCommand

                var entry = counts[peerAddress] ?? (nil, 0)
                entry.count += 1
                if entry.name == nil { entry.name = peerName }
                counts[peerAddress] = entry
            default:
                continue
            }
        }

        return counts
            .map { Peer(address: $0.key, processName: $0.value.name, count: max($0.value.count / 2, 1)) }
            .sorted { ($0.processName ?? $0.address) < ($1.processName ?? $1.address) }
    }
}
