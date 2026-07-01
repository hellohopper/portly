import Foundation

enum PortDiffer {
    struct Diff {
        let newPorts: [PortInfo]
        let deadPinnedPorts: [PortInfo]
    }

    /// Compares two consecutive scans (by port number, since pids change across restarts)
    /// to find ports that newly appeared, and previously-pinned ports that disappeared.
    static func diff(old: [PortInfo], new: [PortInfo], pinned: Set<Int>) -> Diff {
        let oldPortNumbers = Set(old.map(\.port))
        let newPortNumbers = Set(new.map(\.port))

        let newPorts = new.filter { !oldPortNumbers.contains($0.port) }
        let deadPinnedPorts = old.filter { pinned.contains($0.port) && !newPortNumbers.contains($0.port) }

        return Diff(newPorts: newPorts, deadPinnedPorts: deadPinnedPorts)
    }
}
