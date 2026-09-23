import Foundation

public enum PortGrouping {
    public struct Section: Identifiable, Sendable {
        public let title: String
        public let ports: [PortInfo]
        /// A real project (not the "Pinned" or catch-all "Other" buckets), whose
        /// ports make sense to act on as a group.
        public let isProject: Bool
        public var id: String { title }

        public init(title: String, ports: [PortInfo], isProject: Bool = false) {
            self.title = title
            self.ports = ports
            self.isProject = isProject
        }
    }

    /// Pinned ports (by port number) form their own section at the top, regardless
    /// of project. Everything else is grouped by project name, alphabetically,
    /// with ports lacking a resolved project falling into "Other" at the end.
    static let otherTitle = "Other"

    public static func sections(for ports: [PortInfo], pinned: Set<Int>) -> [Section] {
        var sections: [Section] = []

        let pinnedPorts = ports.filter { pinned.contains($0.port) }.sorted { $0.port < $1.port }
        if !pinnedPorts.isEmpty {
            sections.append(Section(title: "Pinned", ports: pinnedPorts))
        }

        let remaining = ports.filter { !pinned.contains($0.port) }
        let grouped = Dictionary(grouping: remaining) { $0.projectName ?? otherTitle }
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            if lhs == otherTitle { return false }
            if rhs == otherTitle { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        for key in sortedKeys {
            let sortedPorts = (grouped[key] ?? []).sorted { $0.port < $1.port }
            // A project literally named "Other" still counts: it has a projectName.
            let isProject = sortedPorts.contains { $0.projectName != nil }
            sections.append(Section(title: key, ports: sortedPorts, isProject: isProject))
        }

        return sections
    }
}
