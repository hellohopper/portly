import Foundation

enum PortDiffer {
    struct Diff {
        let newPorts: [PortInfo]
        /// Every port that disappeared since the previous scan.
        let closedPorts: [PortInfo]
        /// The subset of closedPorts the user had pinned (drives notifications).
        let deadPinnedPorts: [PortInfo]
    }

    /// Compares two consecutive scans (by port number, since pids change across restarts)
    /// to find ports that newly appeared and ports that disappeared.
    static func diff(old: [PortInfo], new: [PortInfo], pinned: Set<Int>) -> Diff {
        let oldPortNumbers = Set(old.map(\.port))
        let newPortNumbers = Set(new.map(\.port))

        let newPorts = new.filter { !oldPortNumbers.contains($0.port) }
        let closedPorts = old.filter { !newPortNumbers.contains($0.port) }
        let deadPinnedPorts = closedPorts.filter { pinned.contains($0.port) }

        return Diff(newPorts: newPorts, closedPorts: closedPorts, deadPinnedPorts: deadPinnedPorts)
    }
}
