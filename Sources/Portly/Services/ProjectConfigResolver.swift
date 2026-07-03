import Foundation

/// Reads an optional `.portly.json` at a project's root so teams can check in
/// expected port labels, e.g.:
///
///     { "labels": { "3000": "web frontend", "8000": "api" } }
///
/// A user's manually-set label always wins over the file's.
final class ProjectConfigResolver: @unchecked Sendable {
    static let shared = ProjectConfigResolver()

    static let fileName = ".portly.json"

    private let lock = NSLock()
    private var cache: [String: (mtime: Date?, labels: [Int: String])] = [:]

    /// Labels from the `.portly.json` at the git root above `directory` (or at
    /// `directory` itself when it isn't in a git repo). Cached by file mtime, so
    /// edits to the file are picked up on the next refresh.
    func labels(fromDirectory directory: String) -> [Int: String] {
        let root = GitProjectResolver.findGitDir(startingAt: directory)?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: directory)
        let configURL = root.appendingPathComponent(Self.fileName)

        let mtime = (try? FileManager.default.attributesOfItem(atPath: configURL.path))?[.modificationDate] as? Date

        lock.lock()
        if let entry = cache[configURL.path], entry.mtime == mtime {
            defer { lock.unlock() }
            return entry.labels
        }
        lock.unlock()

        let labels: [Int: String]
        if mtime != nil, let data = try? Data(contentsOf: configURL) {
            labels = Self.parse(data)
        } else {
            labels = [:]
        }

        lock.lock()
        cache[configURL.path] = (mtime, labels)
        lock.unlock()
        return labels
    }

    /// Tolerant parse: silently drops non-numeric ports and non-string labels
    /// rather than rejecting the whole file.
    static func parse(_ data: Data) -> [Int: String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawLabels = json["labels"] as? [String: Any] else { return [:] }

        var result: [Int: String] = [:]
        for (key, value) in rawLabels {
            guard let port = Int(key), (1...65535).contains(port), let label = value as? String else { continue }
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            result[port] = trimmed
        }
        return result
    }
}
