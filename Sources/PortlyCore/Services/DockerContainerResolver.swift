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
    /// Resolved once and cached: `nil` means "not checked yet", `.some(nil)` means
    /// "checked, no docker CLI found" -- so a missing install isn't re-probed forever.
    private var dockerBinary: String??

    private static let candidateBinaryPaths = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker"
    ]

    private init() {}

    /// Container name per host port, filtered to the ports asked about.
    public func containerNames(for ports: [Int]) async -> [Int: String] {
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
        if let cached = dockerBinary { return cached }
        let found = Self.candidateBinaryPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
        dockerBinary = found
        return found
    }

    private static func queryDocker(binary: String) async -> [Int: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["ps", "--format", "{{.Names}}\t{{.Ports}}"]

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
                guard let colonIndex = hostSide.lastIndex(of: ":"),
                      let hostPort = Int(hostSide[hostSide.index(after: colonIndex)...]) else { continue }
                result[hostPort] = name
            }
        }
        return result
    }
}
