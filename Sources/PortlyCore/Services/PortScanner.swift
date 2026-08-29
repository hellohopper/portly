import Foundation

public enum PortScanner {

    public static func scan() -> [PortInfo] {
        var results: [PortInfo] = []
        results.append(contentsOf: scan(protoFlag: "-iTCP", extraArgs: ["-sTCP:LISTEN"], proto: "TCP"))
        results.append(contentsOf: scan(protoFlag: "-iUDP", extraArgs: [], proto: "UDP"))
        return mergeSamePidAndPort(dedupe(results))
    }

    /// A process listening on both TCP and UDP for the same port shows up as two
    /// otherwise-identical rows; merge those into one row with a combined proto label.
    static func mergeSamePidAndPort(_ entries: [PortInfo]) -> [PortInfo] {
        var order: [String] = []
        var merged: [String: PortInfo] = [:]

        for entry in entries {
            let key = "\(entry.pid)-\(entry.port)"
            if var existing = merged[key] {
                let protocols = existing.proto.split(separator: "+").map(String.init)
                if !protocols.contains(entry.proto) {
                    existing.proto = (protocols + [entry.proto]).joined(separator: "+")
                }
                if entry.isExposedToNetwork && !existing.isExposedToNetwork {
                    existing.bindAddress = entry.bindAddress
                }
                merged[key] = existing
            } else {
                merged[key] = entry
                order.append(key)
            }
        }
        return order.compactMap { merged[$0] }
    }

    /// lsof reports the same pid/port twice when a process listens on both IPv4 and IPv6
    /// sockets; collapse those into a single row.
    static func dedupe(_ entries: [PortInfo]) -> [PortInfo] {
        var indexByKey: [String: Int] = [:]
        var result: [PortInfo] = []
        for entry in entries {
            let key = "\(entry.pid)-\(entry.port)-\(entry.proto)"
            guard let existing = indexByKey[key] else {
                indexByKey[key] = result.count
                result.append(entry)
                continue
            }
            // A process bound to both loopback and every interface is reachable from
            // the network -- the wildcard bind is the one that matters, so don't let
            // whichever lsof happened to list first decide.
            if entry.isExposedToNetwork && !result[existing].isExposedToNetwork {
                result[existing].bindAddress = entry.bindAddress
            }
        }
        return result
    }

    private static func scan(protoFlag: String, extraArgs: [String], proto: String) -> [PortInfo] {
        // -w suppresses the per-unreachable-mount warnings that would otherwise flood
        // stderr on machines with stale network mounts.
        let output = Shell.run("/usr/sbin/lsof", ["-nPw", protoFlag] + extraArgs + ["-F", "pcn"])
        guard let output else { return [] }

        var entries: [PortInfo] = []
        var currentPid: Int32?
        var currentCommand: String = ""

        for rawLine in output.split(separator: "\n") {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())

            switch tag {
            case "p":
                currentPid = Int32(value)
            case "c":
                currentCommand = value
            case "n":
                guard let pid = currentPid, let endpoint = extractEndpoint(from: value) else { continue }
                entries.append(
                    PortInfo(
                        pid: pid,
                        port: endpoint.port,
                        proto: proto,
                        processName: currentCommand,
                        commandPath: nil,
                        bindAddress: endpoint.address
                    )
                )
            default:
                continue
            }
        }
        return entries
    }

    /// lsof "name" field looks like "*:5173", "127.0.0.1:3000", "[::1]:8080", or "192.168.1.5:53->8.8.8.8:53"
    static func extractPort(from name: String) -> Int? {
        extractEndpoint(from: name)?.port
    }

    /// The local address and port a socket is bound to. The address half used to be
    /// parsed and thrown away, but it's the difference between a server only this
    /// machine can reach and one anybody on the same Wi-Fi can.
    static func extractEndpoint(from name: String) -> (address: String, port: Int)? {
        let localPart = name.split(separator: "->").first.map(String.init) ?? name
        guard let lastColon = localPart.lastIndex(of: ":") else { return nil }
        guard let port = Int(localPart[localPart.index(after: lastColon)...]) else { return nil }

        var address = String(localPart[localPart.startIndex..<lastColon])
        // IPv6 literals arrive bracketed: "[::1]:8080".
        if address.hasPrefix("["), address.hasSuffix("]") {
            address = String(address.dropFirst().dropLast())
        }
        return (address, port)
    }
}
