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
        /// Named services the project declares -- a mini Procfile so `portly
        /// workspace up` can start the whole project without everyone remembering (or
        /// agreeing on) the invocation. Each entry is either a bare command string or
        /// an object that also names the port it serves and what must be up first:
        ///
        ///     "commands": {
        ///       "db":  "docker compose up postgres",
        ///       "api": { "run": "uvicorn app:app", "port": 8000, "dependsOn": ["db"] },
        ///       "web": { "run": "npm run dev", "port": 3000, "dependsOn": ["api"] }
        ///     }
        public var services: [String: Service] = [:]

        /// Just the command lines, keyed by service name.
        public var commands: [String: String] {
            get { services.mapValues(\.command) }
            set { services = newValue.mapValues { Service(command: $0) } }
        }

        public init() {}

        public var isEmpty: Bool {
            labels.isEmpty && healthPaths.isEmpty && expectedPorts.isEmpty && tlsPorts.isEmpty && services.isEmpty
        }

        public func healthTarget(for port: Int) -> HealthChecker.Target {
            HealthChecker.Target(path: healthPaths[port] ?? "/", useTLS: tlsPorts.contains(port))
        }
    }

    public struct Service: Sendable, Equatable {
        public var command: String
        /// The port this service listens on once it's ready, if declared. Dependents
        /// wait for it before starting.
        public var port: Int?
        /// Services that must be listening before this one starts.
        public var dependsOn: [String]

        public init(command: String, port: Int? = nil, dependsOn: [String] = []) {
            self.command = command
            self.port = port
            self.dependsOn = dependsOn
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
        config.services = services(json["commands"])
        config.expectedPorts = Set(config.labels.keys)
            .union(portList(json["expects"]))
            .union(config.services.values.compactMap(\.port))
        config.tlsPorts = trueKeys(json["https"])
        return config
    }

    /// Accepts `"name": "command"` or `"name": {"run": ..., "port": ..., "dependsOn": [...]}`.
    private static func services(_ raw: Any?) -> [String: Service] {
        guard let dictionary = raw as? [String: Any] else { return [:] }
        var result: [String: Service] = [:]
        for (key, value) in dictionary {
            let name = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            if let string = value as? String {
                let command = string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !command.isEmpty else { continue }
                result[name] = Service(command: command)
                continue
            }
            guard let object = value as? [String: Any],
                  let run = (object["run"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !run.isEmpty else { continue }
            let port: Int? = {
                if let number = object["port"] as? Int { return (1...65535).contains(number) ? number : nil }
                if let string = object["port"] as? String { return validPort(string) }
                return nil
            }()
            let dependencies: [String]
            if let list = object["dependsOn"] as? [String] {
                dependencies = list
            } else if let single = object["dependsOn"] as? String {
                dependencies = [single]
            } else {
                dependencies = []
            }
            result[name] = Service(
                command: run,
                port: port,
                dependsOn: dependencies.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            )
        }
        return result
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
