import Foundation

public struct PortInfo: Identifiable, Hashable, Sendable {
    public let pid: Int32
    public let port: Int
    public var proto: String        // "TCP", "UDP", or "TCP+UDP" once merged
    public let processName: String
    public let commandPath: String?
    public var projectName: String?
    public var gitBranch: String?
    public var uptimeSeconds: Int?
    public var cpuPercent: Double?
    public var memPercent: Double?
    public var frameworkLabel: String?
    public var commandLine: String?
    public var workingDirectory: String?
    public var bytesInPerSecond: Double?
    public var bytesOutPerSecond: Double?
    /// Ancestor processes (leaf-side first, boundary-limited), e.g. npm wrapping node.
    public var ancestry: [ProcessTreeResolver.Entry] = []

    // Deliberately excludes `proto`: a TCP-only row that gains a UDP listener (or
    // vice versa) merges into "TCP+UDP" on the next scan, and should update in
    // place rather than being treated as a new row (which would break SwiftUI's
    // row animation and any in-progress keyboard focus/scroll on that row).
    public var id: String { "\(pid)-\(port)" }

    public var isDockerManaged: Bool {
        DockerDetector.isDockerManaged(processName: processName)
    }

    /// Case-insensitive substring match against port, process name, framework
    /// label, project name, and git branch -- used to power the search field.
    public func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let needle = trimmed.lowercased()

        let haystacks: [String?] = [
            String(port),
            processName,
            frameworkLabel,
            projectName,
            gitBranch,
            isDockerManaged ? "docker" : nil
        ]
        return haystacks.contains { $0?.lowercased().contains(needle) == true }
    }
}
