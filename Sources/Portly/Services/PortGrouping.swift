import Foundation

enum PortGrouping {
    struct Section: Identifiable {
        let title: String
        let ports: [PortInfo]
        var id: String { title }
    }

    /// Pinned ports (by port number) form their own section at the top, regardless
    /// of project. Everything else is grouped by project name, alphabetically,
    /// with ports lacking a resolved project falling into "Other" at the end.
    static func sections(for ports: [PortInfo], pinned: Set<Int>) -> [Section] {
        var sections: [Section] = []

        let pinnedPorts = ports.filter { pinned.contains($0.port) }.sorted { $0.port < $1.port }
        if !pinnedPorts.isEmpty {
            sections.append(Section(title: "Pinned", ports: pinnedPorts))
        }

        let remaining = ports.filter { !pinned.contains($0.port) }
        let grouped = Dictionary(grouping: remaining) { $0.projectName ?? "Other" }
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            if lhs == "Other" { return false }
            if rhs == "Other" { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        for key in sortedKeys {
            let sortedPorts = (grouped[key] ?? []).sorted { $0.port < $1.port }
            sections.append(Section(title: key, ports: sortedPorts))
        }

        return sections
    }
}
