import Foundation

public enum CommandLineResolver {

    /// Batch-resolves the full (untruncated) command line for the given pids using a
    /// single `ps` call, so framework detection can inspect args like `vite` or `next dev`.
    ///
    /// Read from the kernel where possible; `ps` only runs for processes whose
    /// arguments aren't readable (other users').
    public static func commandLines(for pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }

        var result: [Int32: String] = [:]
        for pid in pids {
            if let argv = ProcessArguments.argv(of: pid) {
                result[pid] = argv.joined(separator: " ")
            }
        }
        let unreadable = pids.filter { result[$0] == nil }
        guard !unreadable.isEmpty else { return result }
        return result.merging(commandLinesFromPs(for: unreadable)) { native, _ in native }
    }

    static func commandLinesFromPs(for pids: [Int32]) -> [Int32: String] {
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
