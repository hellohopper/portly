import Foundation

/// Turns a raw `PortScanner` result into fully-populated rows.
///
/// Shared by the app and the CLI. The CLI used to reimplement a subset of this and
/// had already fallen behind -- no metrics, Docker names or ancestry -- so anything
/// added here now shows up in both.
public enum PortEnricher {

    /// Everything the enrichment pipeline may attach. The CLI runs a cheaper subset:
    /// throughput needs a long-lived `nettop`, which a one-shot command can't sample.
    public struct Options: Sendable {
        public var includeThroughput: Bool
        public var includeAncestry: Bool
        public var includeDockerNames: Bool

        public init(
            includeThroughput: Bool = true,
            includeAncestry: Bool = true,
            includeDockerNames: Bool = true
        ) {
            self.includeThroughput = includeThroughput
            self.includeAncestry = includeAncestry
            self.includeDockerNames = includeDockerNames
        }

        public static let full = Options()
        /// No long-lived sampler available, so no throughput.
        public static let oneShot = Options(includeThroughput: false)
    }

    /// Memoised per-process project context. The caller owns it so it can persist
    /// across refreshes; entries are validated against process start time, since a
    /// reused pid is a different process with a different working directory.
    public struct ProjectContext: Sendable {
        public let projectName: String?
        public let gitBranch: String?
        public let workingDirectory: String?
        public let startTime: TimeInterval?

        public init(
            projectName: String?,
            gitBranch: String?,
            workingDirectory: String?,
            startTime: TimeInterval?
        ) {
            self.projectName = projectName
            self.gitBranch = gitBranch
            self.workingDirectory = workingDirectory
            self.startTime = startTime
        }
    }

    public struct Result: Sendable {
        public let ports: [PortInfo]
        /// port -> label contributed by some project's `.portly.json`.
        public let projectConfigLabels: [Int: String]
        /// Merged `.portly.json` config across every project represented in the scan,
        /// for lookups that don't care which project a setting came from.
        public let projectConfig: ProjectConfigResolver.Config
        /// Per-project-root configs, keeping the attribution the merged view loses.
        public let configsByProjectRoot: [String: ProjectConfigResolver.Config]
        /// Which project root each listening port currently belongs to.
        public let projectRootByPort: [Int: String]
        /// The project-context cache, to be fed back into the next call.
        public let contextCache: [Int32: ProjectContext]
    }

    public static func enrich(
        _ scanned: [PortInfo],
        options: Options = .full,
        contextCache: [Int32: ProjectContext] = [:]
    ) async -> Result {
        let uniquePids = Array(Set(scanned.map(\.pid)))
        // One `ps -axo` covers uptime, %CPU, %MEM and the ancestry table; only the
        // full command line (whose argv contains spaces) needs its own call.
        let table = ProcessTable.snapshot()
        let uptimes = table.uptimeSeconds(for: uniquePids)
        let metrics = table.metrics(for: uniquePids)
        let commandLines = CommandLineResolver.commandLines(for: uniquePids)
        let ancestryTable = options.includeAncestry ? table.ancestryTable : [:]

        var cache = contextCache
        var enriched: [PortInfo] = []
        enriched.reserveCapacity(scanned.count)

        for var info in scanned {
            let context = projectContext(
                for: info.pid, startedAt: table.startTime(of: info.pid), cache: &cache
            )
            info.projectName = context.projectName
            info.gitBranch = context.gitBranch
            info.workingDirectory = context.workingDirectory
            info.uptimeSeconds = uptimes[info.pid]
            info.cpuPercent = metrics[info.pid]?.cpuPercent
            info.memPercent = metrics[info.pid]?.memPercent

            if options.includeThroughput {
                if let throughput = NetworkThroughputResolver.shared.throughput(for: info.pid) {
                    info.bytesInPerSecond = throughput.bytesInPerSecond
                    info.bytesOutPerSecond = throughput.bytesOutPerSecond
                }
                info.throughputHistory = NetworkThroughputResolver.shared.history(for: info.pid)
            }
            if let commandLine = commandLines[info.pid] {
                info.commandLine = commandLine
                info.frameworkLabel = FrameworkDetector.detect(
                    processName: info.processName, commandLine: commandLine
                )
            }
            if options.includeAncestry {
                info.ancestry = ProcessTreeResolver.ancestry(of: info.pid, in: ancestryTable)
            }
            enriched.append(info)
        }

        if options.includeDockerNames {
            let dockerPorts = enriched.filter(\.isDockerManaged).map(\.port)
            let containerNames = await DockerContainerResolver.shared.containerNames(for: dockerPorts)
            for index in enriched.indices {
                enriched[index].dockerContainerName = containerNames[enriched[index].port]
            }
        }

        // Resolve each distinct working directory to its project root once, then keep
        // the per-root config separate: merging them loses the attribution that
        // conflict detection needs ("3000 is `web`'s port, but `admin` holds it").
        var rootByDirectory: [String: String] = [:]
        var configsByRoot: [String: ProjectConfigResolver.Config] = [:]
        for directory in Set(enriched.compactMap(\.workingDirectory)) {
            let root = GitProjectResolver.projectRoot(fromDirectory: directory).path
            rootByDirectory[directory] = root
            if configsByRoot[root] == nil {
                configsByRoot[root] = ProjectConfigResolver.shared.config(fromDirectory: directory)
            }
        }

        var merged = ProjectConfigResolver.Config()
        for config in configsByRoot.values {
            // First project to claim a port wins; overlaps across projects are rare.
            merged.labels.merge(config.labels) { current, _ in current }
            merged.healthPaths.merge(config.healthPaths) { current, _ in current }
            merged.expectedPorts.formUnion(config.expectedPorts)
            merged.tlsPorts.formUnion(config.tlsPorts)
        }

        let rootByPort = Dictionary(
            enriched.compactMap { info -> (Int, String)? in
                guard let directory = info.workingDirectory, let root = rootByDirectory[directory] else { return nil }
                return (info.port, root)
            },
            uniquingKeysWith: { current, _ in current }
        )

        return Result(
            ports: enriched,
            projectConfigLabels: merged.labels,
            projectConfig: merged,
            configsByProjectRoot: configsByRoot.filter { !$0.value.isEmpty },
            projectRootByPort: rootByPort,
            contextCache: cache
        )
    }

    /// Resolves a process's project context, memoised for the lifetime of that
    /// process. Validated against start time as well as pid: after pid reuse the
    /// number alone would hand a new process the dead one's project and working
    /// directory, sending "open in editor" and restart to the wrong repository.
    static func projectContext(
        for pid: Int32,
        startedAt: TimeInterval?,
        cache: inout [Int32: ProjectContext]
    ) -> ProjectContext {
        // `ps` reports elapsed time in whole seconds, so a process's derived start
        // time can wobble by a second between snapshots.
        if let cached = cache[pid], isSameProcess(cached.startTime, startedAt) {
            return cached
        }
        // One lsof for the cwd, then pure filesystem reads from there.
        let workingDirectory = GitProjectResolver.workingDirectory(of: pid)
        let resolved = workingDirectory.map(GitProjectResolver.resolve(workingDirectory:))
        let context = ProjectContext(
            projectName: resolved?.projectName,
            gitBranch: resolved?.gitBranch,
            workingDirectory: workingDirectory,
            startTime: startedAt
        )
        cache[pid] = context
        return context
    }

    static func isSameProcess(_ cached: TimeInterval?, _ current: TimeInterval?) -> Bool {
        guard let cached, let current else { return cached == nil && current == nil }
        return abs(cached - current) <= 2
    }
}
