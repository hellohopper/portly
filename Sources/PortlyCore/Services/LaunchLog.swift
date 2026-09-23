import Foundation

/// Where processes Portly starts write their output.
///
/// A relaunched server used to inherit Portly's own stdout -- /dev/null for a menu
/// bar app -- so the moment it crashed on startup, the reason was gone. Each launch
/// now appends to `~/Library/Logs/Portly/<name>.log`, which the "Open log file" /
/// "Show log" actions and `portly logs` then find like any other log the process
/// has open.
public enum LaunchLog {

    /// Rotated to `<name>.log.1` at launch once it grows past this.
    static let rotationThreshold: UInt64 = 5 * 1024 * 1024

    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Portly", isDirectory: true)
    }

    /// A filesystem-safe log name, e.g. ("my app", "web") -> "my-app-web".
    public static func name(_ parts: String?...) -> String {
        let joined = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "-")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitized = String(joined.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return sanitized.isEmpty ? "process" : String(sanitized.prefix(100))
    }

    public static func url(for name: String, in directory: URL = LaunchLog.directory) -> URL {
        directory.appendingPathComponent("\(name).log")
    }

    /// Opens (creating/rotating as needed) the log for appending, and writes a header
    /// separating this run from the previous one.
    public static func open(
        name: String,
        commandLine: String,
        workingDirectory: String?,
        in directory: URL = LaunchLog.directory,
        now: Date = Date()
    ) -> FileHandle? {
        let fileManager = FileManager.default
        let fileURL = url(for: name, in: directory)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if let size = (try? fileManager.attributesOfItem(atPath: fileURL.path))?[.size] as? UInt64,
               size > rotationThreshold {
                let rotated = fileURL.appendingPathExtension("1")
                try? fileManager.removeItem(at: rotated)
                try fileManager.moveItem(at: fileURL, to: rotated)
            }
            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            let header = "\n=== \(ISO8601DateFormatter().string(from: now)) \(commandLine)"
                + (workingDirectory.map { " (in \($0))" } ?? "") + "\n"
            try handle.write(contentsOf: Data(header.utf8))
            return handle
        } catch {
            return nil
        }
    }

    /// The last `maxLines` lines of a file, reading at most `maxBytes` from its end so
    /// a huge log never gets loaded whole.
    public static func tail(of path: String, maxLines: Int = 200, maxBytes: Int = 128 * 1024) -> [String] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return [] }
        let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd() else { return [] }
        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        // Starting mid-file means the first line is probably partial.
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        if lines.last == "" { lines.removeLast() }
        return Array(lines.suffix(maxLines))
    }
}
