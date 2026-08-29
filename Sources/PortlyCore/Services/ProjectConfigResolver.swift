import Foundation

/// Reads an optional `.portly.json` at a project's root so teams can check in
/// expected port labels, health endpoints, and TLS, e.g.:
///
///     {
///       "labels": { "3000": "web frontend", "8000": "api" },
///       "health": { "8000": "/api/health" },
///       "https":  { "3000": true }
///     }
///
/// A user's manually-set label always wins over the file's.
public final class ProjectConfigResolver: @unchecked Sendable {
    public static let shared = ProjectConfigResolver()

    public static let fileName = ".portly.json"

    /// Everything a project can declare about its ports.
    public struct Config: Sendable, Equatable {
        public var labels: [Int: String] = [:]
        /// Port -> health-check path, so an API that 404s on "/" can point at its
        /// real health endpoint instead of showing a permanent orange badge.
        public var healthPaths: [Int: String] = [:]
        /// Ports the project expects to serve on, whether or not they're up.
        public var expectedPorts: Set<Int> = []
        /// Ports served over TLS, so the probe uses https://.
        public var tlsPorts: Set<Int> = []

        public init() {}

        public var isEmpty: Bool {
            labels.isEmpty && healthPaths.isEmpty && expectedPorts.isEmpty && tlsPorts.isEmpty
        }

        public func healthTarget(for port: Int) -> HealthChecker.Target {
            HealthChecker.Target(path: healthPaths[port] ?? "/", useTLS: tlsPorts.contains(port))
        }
    }

    private let lock = NSLock()
    private var cache: [String: (mtime: Date?, config: Config)] = [:]

    /// The config from the `.portly.json` at the git root above `directory` (or at
    /// `directory` itself when it isn't in a git repo). Cached by file mtime, so
    /// edits to the file are picked up on the next refresh.
    public func config(fromDirectory directory: String) -> Config {
        let root = GitProjectResolver.projectRoot(fromDirectory: directory)
        let configURL = root.appendingPathComponent(Self.fileName)

        let mtime = (try? FileManager.default.attributesOfItem(atPath: configURL.path))?[.modificationDate] as? Date

        lock.lock()
        if let entry = cache[configURL.path], entry.mtime == mtime {
            defer { lock.unlock() }
            return entry.config
        }
        lock.unlock()

        let config: Config
        if mtime != nil, let data = try? Data(contentsOf: configURL) {
            config = Self.parse(data)
        } else {
            config = Config()
        }

        lock.lock()
        cache[configURL.path] = (mtime, config)
        lock.unlock()
        return config
    }

    public func labels(fromDirectory directory: String) -> [Int: String] {
        config(fromDirectory: directory).labels
    }

    /// Tolerant parse: silently drops entries with non-numeric ports or wrong-typed
    /// values rather than rejecting the whole file.
    static func parse(_ data: Data) -> Config {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Config() }

        var config = Config()
        config.labels = stringMap(json["labels"])
        config.healthPaths = stringMap(json["health"])
        config.expectedPorts = Set(config.labels.keys).union(portList(json["expects"]))
        config.tlsPorts = trueKeys(json["https"])
        return config
    }

    private static func stringMap(_ raw: Any?) -> [Int: String] {
        guard let dictionary = raw as? [String: Any] else { return [:] }
        var result: [Int: String] = [:]
        for (key, value) in dictionary {
            guard let port = validPort(key), let string = value as? String else { continue }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            result[port] = trimmed
        }
        return result
    }

    private static func trueKeys(_ raw: Any?) -> Set<Int> {
        guard let dictionary = raw as? [String: Any] else { return [] }
        return Set(dictionary.compactMap { key, value in
            (value as? Bool) == true ? validPort(key) : nil
        })
    }

    /// Accepts either ["3000", "8000"] or [3000, 8000].
    private static func portList(_ raw: Any?) -> Set<Int> {
        if let numbers = raw as? [Int] { return Set(numbers.filter { (1...65535).contains($0) }) }
        if let strings = raw as? [String] { return Set(strings.compactMap(validPort)) }
        return []
    }

    private static func validPort(_ key: String) -> Int? {
        guard let port = Int(key), (1...65535).contains(port) else { return nil }
        return port
    }
}
