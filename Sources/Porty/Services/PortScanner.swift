import Foundation

enum PortScanner {

    static func scan() -> [PortInfo] {
        var results: [PortInfo] = []
        results.append(contentsOf: scan(protoFlag: "-iTCP", extraArgs: ["-sTCP:LISTEN"], proto: "TCP"))
        results.append(contentsOf: scan(protoFlag: "-iUDP", extraArgs: [], proto: "UDP"))
        return dedupe(results)
    }

    /// lsof reports the same pid/port twice when a process listens on both IPv4 and IPv6
    /// sockets; collapse those into a single row.
    private static func dedupe(_ entries: [PortInfo]) -> [PortInfo] {
        var seen = Set<String>()
        var result: [PortInfo] = []
        for entry in entries {
            let key = "\(entry.pid)-\(entry.port)-\(entry.proto)"
            if seen.insert(key).inserted {
                result.append(entry)
            }
        }
        return result
    }

    private static func scan(protoFlag: String, extraArgs: [String], proto: String) -> [PortInfo] {
        let output = run("/usr/sbin/lsof", args: ["-nP", protoFlag] + extraArgs + ["-F", "pcn"])
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
                guard let pid = currentPid, let port = extractPort(from: value) else { continue }
                entries.append(
                    PortInfo(
                        pid: pid,
                        port: port,
                        proto: proto,
                        processName: currentCommand,
                        commandPath: nil
                    )
                )
            default:
                continue
            }
        }
        return entries
    }

    /// lsof "name" field looks like "*:5173", "127.0.0.1:3000", "[::1]:8080", or "192.168.1.5:53->8.8.8.8:53"
    private static func extractPort(from name: String) -> Int? {
        let localPart = name.split(separator: "->").first.map(String.init) ?? name
        guard let lastColon = localPart.lastIndex(of: ":") else { return nil }
        let portString = localPart[localPart.index(after: lastColon)...]
        return Int(portString)
    }

    private static func run(_ path: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
