import Foundation

public enum PortDiffer {
    public struct Diff: Sendable {
        public let newPorts: [PortInfo]
        /// Every port that disappeared since the previous scan.
        public let closedPorts: [PortInfo]
        /// The subset of closedPorts the user had pinned (drives notifications).
        public let deadPinnedPorts: [PortInfo]
        /// Ports still listening but now held by a *different* process than last scan --
        /// a restart that completed inside one poll interval. Comparing port numbers
        /// alone renders these invisible, so a server that crashed and was respawned
        /// left no trace in history at all.
        public let replacedPorts: [PortInfo]
    }

    /// Compares two consecutive scans to find ports that appeared, disappeared, or
    /// changed hands.
    ///
    /// Appearance and disappearance are judged by port *number*, not pid: a dev server
    /// restarting keeps its port and should read as a replacement, not as a death
    /// followed by a birth (which would fire a "pinned port stopped" alert for a
    /// server that is, in fact, still up).
    public static func diff(old: [PortInfo], new: [PortInfo], pinned: Set<Int>) -> Diff {
        let oldPortNumbers = Set(old.map(\.port))
        let newPortNumbers = Set(new.map(\.port))

        let newPorts = new.filter { !oldPortNumbers.contains($0.port) }
        let closedPorts = old.filter { !newPortNumbers.contains($0.port) }
        let deadPinnedPorts = closedPorts.filter { pinned.contains($0.port) }

        // Same port, different owner. Keyed on the set of pids holding each port so a
        // port legitimately shared by two processes doesn't churn on ordering.
        var oldPidsByPort: [Int: Set<Int32>] = [:]
        for info in old { oldPidsByPort[info.port, default: []].insert(info.pid) }
        let replacedPorts = new.filter { info in
            guard let previousPids = oldPidsByPort[info.port] else { return false }
            return !previousPids.contains(info.pid)
        }

        return Diff(
            newPorts: newPorts,
            closedPorts: closedPorts,
            deadPinnedPorts: deadPinnedPorts,
            replacedPorts: replacedPorts
        )
    }
}
