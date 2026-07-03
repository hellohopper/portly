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

        // Fields: time, "processName.pid", bytes_in, bytes_out, (trailing empty).
        // Process names can contain commas (nettop doesn't escape them), which shifts
        // the column positions -- so anchor on the *end* of the line, not fixed indexes.
        var fields = trimmed.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        if fields.last?.isEmpty == true {
            fields.removeLast()
        }
        guard fields.count >= 4 else { return nil }

        // The pid is the last dot-separated segment of the name column, whose final
        // fragment sits just before bytes_in even when the name itself had commas.
        let processAndPid = fields[fields.count - 3]
        guard let lastDot = processAndPid.lastIndex(of: "."),
              let pid = Int32(processAndPid[processAndPid.index(after: lastDot)...]) else { return nil }
        guard let bytesIn = Double(fields[fields.count - 2]),
              let bytesOut = Double(fields[fields.count - 1]) else { return nil }

        return Sample(pid: pid, bytesIn: bytesIn, bytesOut: bytesOut)
    }
}
