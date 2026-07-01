import Foundation

enum UptimeResolver {

    /// Batch-resolves elapsed running time (in seconds) for the given pids using a single `ps` call.
    static func elapsedSeconds(for pids: [Int32]) -> [Int32: Int] {
        guard !pids.isEmpty else { return [:] }

        let pidList = pids.map(String.init).joined(separator: ",")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "pid=,etime=", "-p", pidList]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var result: [Int32: Int] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
            guard let seconds = parseElapsed(String(parts[1])) else { continue }
            result[pid] = seconds
        }
        return result
    }

    /// Parses macOS `ps etime` format: "[[dd-]hh:]mm:ss"
    private static func parseElapsed(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        var days = 0
        var rest = trimmed

        if let dashRange = trimmed.range(of: "-") {
            days = Int(trimmed[trimmed.startIndex..<dashRange.lowerBound]) ?? 0
            rest = String(trimmed[dashRange.upperBound...])
        }

        let components = rest.split(separator: ":").compactMap { Int($0) }
        switch components.count {
        case 2: // mm:ss
            return days * 86400 + components[0] * 60 + components[1]
        case 3: // hh:mm:ss
            return days * 86400 + components[0] * 3600 + components[1] * 60 + components[2]
        default:
            return nil
        }
    }

    /// Formats seconds into a compact human string, e.g. "2m", "1h 3m", "3d 2h".
    static func format(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(secs)s"
    }
}
