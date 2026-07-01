import Foundation

struct PortInfo: Identifiable, Hashable {
    let pid: Int32
    let port: Int
    var proto: String        // "TCP", "UDP", or "TCP+UDP" once merged
    let processName: String
    let commandPath: String?
    var projectName: String?
    var gitBranch: String?
    var uptimeSeconds: Int?
    var cpuPercent: Double?
    var memPercent: Double?
    var frameworkLabel: String?
    var commandLine: String?
    var workingDirectory: String?

    var id: String { "\(pid)-\(port)-\(proto)" }

    var isDockerManaged: Bool {
        DockerDetector.isDockerManaged(processName: processName)
    }

    /// Case-insensitive substring match against port, process name, framework
    /// label, project name, and git branch -- used to power the search field.
    func matches(query: String) -> Bool {
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
