import Foundation

enum CommandLineResolver {

    /// Batch-resolves the full (untruncated) command line for the given pids using a
    /// single `ps` call, so framework detection can inspect args like `vite` or `next dev`.
    static func commandLines(for pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }

        let pidList = pids.map(String.init).joined(separator: ",")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ww", "-o", "pid=,command=", "-p", pidList]

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
