import Foundation

/// Resolves which Docker container owns a host-forwarded port, via `docker ps`
/// (the container's own process never shows up in macOS `lsof`/`ps` -- it's running
/// inside Docker Desktop's Linux VM, only the host-side forwarder does).
public actor DockerContainerResolver {
    public static let shared = DockerContainerResolver()

    /// `docker ps` talks to the daemon over a socket -- worth caching briefly rather
    /// than re-running it on every 2s port-list refresh.
    private let cacheInterval: TimeInterval = 5
    private var lastFetch: Date?
    private var portToName: [Int: String] = [:]
    /// Cached so a missing Docker install isn't re-probed on every refresh.
    private enum BinaryLookup {
        case unchecked
        case missing
        case found(String)
    }
    private var dockerBinary: BinaryLookup = .unchecked

    private static let candidateBinaryPaths = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker"
    ]

    private init() {}

    /// Container name per host port, filtered to the ports asked about.
    public func containerNames(for ports: [Int]) async -> [Int: String] {
        // No Docker-managed ports in this scan means there is nothing to resolve --
        // don't shell out to the daemon (which may be hung) just to filter to nothing.
        guard !ports.isEmpty else { return [:] }
        await refreshIfNeeded()
        let wanted = Set(ports)
        return portToName.filter { wanted.contains($0.key) }
    }

    private func refreshIfNeeded() async {
        let now = Date()
        if let lastFetch, now.timeIntervalSince(lastFetch) < cacheInterval { return }
        lastFetch = now

        guard let binary = resolveDockerBinary() else {
            portToName = [:]
            return
        }
        portToName = await Self.queryDocker(binary: binary)
    }

    private func resolveDockerBinary() -> String? {
        switch dockerBinary {
        case .found(let path): return path
        case .missing: return nil
        case .unchecked:
            let found = Self.candidateBinaryPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
            dockerBinary = found.map { BinaryLookup.found($0) } ?? .missing
            return found
        }
    }

    /// `docker stop <name>`. Killing a Docker-forwarded port's *pid* would SIGTERM
    /// `com.docker.backend` -- the host-side forwarder shared by every container --
    /// rather than the container the user meant, so those rows route here instead.
    /// `docker stop` allows a 10s grace period by default, hence the longer timeout.
    public func stop(containerName: String) async -> Bool {
        guard let binary = resolveDockerBinary() else { return false }
        lastFetch = nil // the port map is about to change
        return Shell.succeeds(binary, ["stop", containerName], timeout: 20)
    }

    public func restart(containerName: String) async -> Bool {
        guard let binary = resolveDockerBinary() else { return false }
        lastFetch = nil
        return Shell.succeeds(binary, ["restart", containerName], timeout: 30)
    }

    private static func queryDocker(binary: String) async -> [Int: String] {
        // A wedged Docker VM (common after sleep) makes `docker ps` hang indefinitely;
        // without a timeout that stalls this actor and, behind it, every port refresh.
        guard let output = Shell.run(binary, ["ps", "--format", "{{.Names}}\t{{.Ports}}"], timeout: 3) else {
            return [:]
        }
        return parse(output)
    }

    /// Parses lines like `myapp-web-1\t0.0.0.0:3000->3000/tcp, :::3000->3000/tcp`.
    static func parse(_ output: String) -> [Int: String] {
        var result: [Int: String] = [:]
        for line in output.split(separator: "\n") {
            let columns = line.split(separator: "\t", maxSplits: 1)
            guard columns.count == 2 else { continue }
            let name = String(columns[0])

            for mapping in columns[1].split(separator: ",") {
                let trimmed = mapping.trimmingCharacters(in: .whitespaces)
                guard let arrowRange = trimmed.range(of: "->") else { continue }
                let hostSide = trimmed[trimmed.startIndex..<arrowRange.lowerBound]
                guard let colonIndex = hostSide.lastIndex(of: ":") else { continue }
                // The host side is a single port ("8000") or, for `-p 8000-8002:...`,
                // a range -- expand the range so every row in it resolves a name.
                for hostPort in expandPorts(String(hostSide[hostSide.index(after: colonIndex)...])) {
                    result[hostPort] = name
                }
            }
        }
        return result
    }

    /// "8000" -> [8000]; "8000-8002" -> [8000, 8001, 8002].
    static func expandPorts(_ raw: String) -> [Int] {
        if let single = Int(raw) { return [single] }
        let bounds = raw.split(separator: "-")
        guard bounds.count == 2,
              let low = Int(bounds[0]), let high = Int(bounds[1]),
              low <= high, high - low <= 1024 else { return [] }
        return Array(low...high)
    }
}
