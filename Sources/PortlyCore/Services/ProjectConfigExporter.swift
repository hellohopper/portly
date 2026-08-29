import Foundation

/// Turns the labels a user set by hand into a `.portly.json` their team can check in.
public enum ProjectConfigExporter {

    public struct Project: Identifiable, Sendable, Equatable {
        public let root: URL
        public let labels: [Int: String]
        public var id: String { root.path }
        public var name: String { root.lastPathComponent }

        public init(root: URL, labels: [Int: String]) {
            self.root = root
            self.labels = labels
        }
    }

    /// Groups manually-labelled ports by the project root they belong to. Ports with
    /// no manual label, or no resolvable working directory, contribute nothing.
    public static func exportableProjects(
        ports: [PortInfo],
        manualLabels: [Int: String]
    ) -> [Project] {
        var byRoot: [URL: [Int: String]] = [:]
        for info in ports {
            guard let label = manualLabels[info.port], let workingDirectory = info.workingDirectory else { continue }
            let root = GitProjectResolver.projectRoot(fromDirectory: workingDirectory)
            byRoot[root, default: [:]][info.port] = label
        }
        return byRoot.map { Project(root: $0.key, labels: $0.value) }
            .sorted { $0.name < $1.name }
    }

    /// Manual labels win, but entries the file already had for ports that aren't
    /// currently listening survive -- exporting is meant to update the file, not
    /// replace it with a snapshot of whatever happens to be running right now.
    public static func merge(existing: [Int: String], manual: [Int: String]) -> [Int: String] {
        var merged = existing
        merged.merge(manual) { _, manual in manual }
        return merged
    }

    public static func encode(labels: [Int: String]) -> Data? {
        let payload = ["labels": Dictionary(uniqueKeysWithValues: labels.map { (String($0.key), $0.value) })]
        return try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    /// Writes (creating or updating) the `.portly.json` at a project's root.
    @discardableResult
    public static func write(_ project: Project) -> URL? {
        let configURL = project.root.appendingPathComponent(ProjectConfigResolver.fileName)
        let existing = ProjectConfigResolver.shared.labels(fromDirectory: project.root.path)
        guard let data = encode(labels: merge(existing: existing, manual: project.labels)) else { return nil }
        do {
            try data.write(to: configURL)
            return configURL
        } catch {
            return nil
        }
    }
}
