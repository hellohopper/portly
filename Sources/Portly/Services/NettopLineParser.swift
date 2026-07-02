import Foundation

/// Pure parsing for `nettop -P -d -x -J bytes_in,bytes_out` CSV output, kept separate
/// from process management so the format (which is easy to get subtly wrong -- process
/// names can themselves contain dots, so the pid is always the *last* dot-separated
/// segment) can be unit tested without spawning a real process.
enum NettopLineParser {
    struct Sample: Equatable {
        let pid: Int32
        let bytesIn: Double
        let bytesOut: Double
    }

    /// Each new sample block starts with a fresh CSV header line (e.g. in `-l 0`
    /// continuous logging mode, one header per interval).
    static func isHeaderLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("time,")
    }

    static func parseDataLine(_ line: String) -> Sample? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isHeaderLine(trimmed) else { return nil }

        let fields = trimmed.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        // Fields: time, "processName.pid", bytes_in, bytes_out, (trailing empty)
        guard fields.count >= 4 else { return nil }

        let processAndPid = fields[1]
        guard let lastDot = processAndPid.lastIndex(of: "."),
              let pid = Int32(processAndPid[processAndPid.index(after: lastDot)...]) else { return nil }
        guard let bytesIn = Double(fields[2]), let bytesOut = Double(fields[3]) else { return nil }

        return Sample(pid: pid, bytesIn: bytesIn, bytesOut: bytesOut)
    }
}
