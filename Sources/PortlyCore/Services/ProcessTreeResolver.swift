import Foundation

/// Resolves the ancestry of a process (e.g. `npm run dev` → `node`) so wrapper-managed
/// dev servers can be understood -- and killed -- at the root instead of just the leaf.
public enum ProcessTreeResolver {

    public struct Entry: Hashable {
        public let pid: Int32
        public let name: String
    }

    /// Ancestors that mark the edge of the "interesting" tree: climbing past a shell,
    /// terminal, IDE, or launchd would make "kill process tree" dangerous.
    static let boundaryNames: Set<String> = [
        "launchd", "login", "sh", "bash", "zsh", "fish", "tcsh", "csh", "dash",
        "Terminal", "iTerm2", "tmux", "screen",
        "Code Helper", "Code Helper (Plugin)", "Electron", "Cursor Helper (Plugin)", "node_helper"
    ]

    /// Builds a pid -> (ppid, executable name) table from one `ps` call.
    public static func snapshot() -> [Int32: (ppid: Int32, name: String)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,comm="]

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
        return parseTable(output)
    }

    static func parseTable(_ output: String) -> [Int32: (ppid: Int32, name: String)] {
        var table: [Int32: (ppid: Int32, name: String)] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Format: "<pid> <ppid> <command path>"; the path may contain spaces.
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }
            let name = URL(fileURLWithPath: String(parts[2])).lastPathComponent
            table[pid] = (ppid, name)
        }
        return table
    }

    /// Walks upward from (but not including) `pid`, returning ancestors leaf-side
    /// first, stopping before boundary processes, pid 1, cycles, or 6 levels.
    public static func ancestry(of pid: Int32, in table: [Int32: (ppid: Int32, name: String)]) -> [Entry] {
        var chain: [Entry] = []
        var visited: Set<Int32> = [pid]
        var current = pid

        while chain.count < 6 {
            guard let node = table[current], node.ppid > 1, !visited.contains(node.ppid) else { break }
            guard let parent = table[node.ppid] else { break }
            if boundaryNames.contains(parent.name) { break }
            chain.append(Entry(pid: node.ppid, name: parent.name))
            visited.insert(node.ppid)
            current = node.ppid
        }
        return chain
    }

    /// Human-readable chain, outermost wrapper first: "npm → node".
    public static func describe(leafName: String, ancestry: [Entry]) -> String {
        (ancestry.reversed().map(\.name) + [leafName]).joined(separator: " → ")
    }
}
