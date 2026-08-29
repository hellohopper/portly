import Foundation

/// Finds a log file a process is writing to.
///
/// Honestly hit-or-miss: a dev server run in the foreground writes to a tty, and
/// there is no file to open. It pays off for detached processes (`pm2`, `nohup`, a
/// launchd agent) where "reveal the owning terminal" has nothing to offer. Callers
/// should only surface the action when this actually finds something, never as a
/// promise.
public enum LogFileResolver {

    private static let logExtensions: Set<String> = ["log", "out", "err", "txt"]

    /// The most plausible log file the process has open for writing, preferring files
    /// under its own project directory over system-wide locations.
    public static func logFile(pid: Int32, workingDirectory: String?) -> String? {
        candidates(pid: pid, workingDirectory: workingDirectory).first
    }

    public static func candidates(pid: Int32, workingDirectory: String?) -> [String] {
        // Fields arrive per descriptor in f → a → t → n order; `a` (access mode) has
        // to be requested explicitly, it isn't part of the default set.
        guard let output = Shell.run("/usr/sbin/lsof", ["-w", "-p", "\(pid)", "-F", "ftan"]) else { return [] }
        return rank(parse(output), workingDirectory: workingDirectory)
    }

    /// Parses `-F ftan` output, keeping regular files opened for writing.
    static func parse(_ output: String) -> [String] {
        var isWritable = false
        var isRegularFile = false
        var paths: [String] = []

        for rawLine in output.split(separator: "\n") {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())

            switch tag {
            case "f":
                // New descriptor: reset until its own mode and type lines arrive.
                isWritable = false
                isRegularFile = false
            case "a":
                // "w" (write) or "u" (read/write); "r" is read-only.
                isWritable = value.contains("w") || value.contains("u")
            case "t":
                isRegularFile = value == "REG"
            case "n":
                guard isRegularFile, isWritable, value.hasPrefix("/") else { continue }
                paths.append(value)
            default:
                continue
            }
        }
        return paths
    }

    static func rank(_ paths: [String], workingDirectory: String?) -> [String] {
        paths
            .filter { path in
                let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
                let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
                return logExtensions.contains(ext) || name.contains("log")
            }
            .sorted { lhs, rhs in
                // A log inside the project beats one in a shared system location.
                let lhsLocal = workingDirectory.map(lhs.hasPrefix) ?? false
                let rhsLocal = workingDirectory.map(rhs.hasPrefix) ?? false
                if lhsLocal != rhsLocal { return lhsLocal }
                return lhs < rhs
            }
    }
}
