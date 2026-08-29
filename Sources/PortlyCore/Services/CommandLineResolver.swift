import Foundation

public enum CommandLineResolver {

    /// Batch-resolves the full (untruncated) command line for the given pids using a
    /// single `ps` call, so framework detection can inspect args like `vite` or `next dev`.
    public static func commandLines(for pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }

        let pidList = pids.map(String.init).joined(separator: ",")
        guard let output = Shell.run("/bin/ps", ["-ww", "-o", "pid=,command=", "-p", pidList]) else { return [:] }

        var result: [Int32: String] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let firstSpace = trimmed.firstIndex(of: " ") else { continue }
            guard let pid = Int32(trimmed[trimmed.startIndex..<firstSpace]) else { continue }
            let command = trimmed[trimmed.index(after: firstSpace)...].trimmingCharacters(in: .whitespaces)
            result[pid] = command
        }
        return result
    }
}
