import Foundation

/// One `ps` call covering everything the port list needs per refresh: uptime, %CPU,
/// %MEM, and the parent/name table used for process ancestry.
///
/// These used to be three separate `ps -p <pids>` invocations plus a fourth
/// `ps -axo` for the tree. All five leading columns are whitespace-free, so a single
/// `ps -axo pid=,ppid=,etime=,pcpu=,pmem=,comm=` parses unambiguously with a bounded
/// split -- only `command=` still needs its own call, because argv contains spaces.
public struct ProcessTable: Sendable {

    public struct Entry: Sendable {
        public let ppid: Int32
        public let name: String
        public let uptimeSeconds: Int?
        public let cpuPercent: Double?
        public let memPercent: Double?
    }

    public private(set) var entries: [Int32: Entry]
    /// System uptime when this snapshot was taken, used to turn each entry's elapsed
    /// time into a stable start time.
    public let takenAtSystemUptime: TimeInterval

    public init(entries: [Int32: Entry], takenAtSystemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.entries = entries
        self.takenAtSystemUptime = takenAtSystemUptime
    }

    public static func snapshot() -> ProcessTable {
        let takenAt = ProcessInfo.processInfo.systemUptime
        guard let output = Shell.run("/bin/ps", ["-axo", "pid=,ppid=,etime=,pcpu=,pmem=,comm="]) else {
            return ProcessTable(entries: [:], takenAtSystemUptime: takenAt)
        }
        return ProcessTable(entries: parse(output), takenAtSystemUptime: takenAt)
    }

    /// When a process started, as seconds since boot. Unlike elapsed time this doesn't
    /// change between snapshots, so it can identify a process across refreshes and
    /// distinguish a reused pid from the original holder.
    public func startTime(of pid: Int32) -> TimeInterval? {
        guard let uptime = entries[pid]?.uptimeSeconds else { return nil }
        return takenAtSystemUptime - TimeInterval(uptime)
    }

    static func parse(_ output: String) -> [Int32: Entry] {
        var table: [Int32: Entry] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // "<pid> <ppid> <etime> <pcpu> <pmem> <command path>" -- only the trailing
            // path may contain spaces, so cap the split at 5.
            let parts = trimmed.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard parts.count == 6, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }
            table[pid] = Entry(
                ppid: ppid,
                name: URL(fileURLWithPath: String(parts[5])).lastPathComponent,
                uptimeSeconds: UptimeResolver.parseElapsed(String(parts[2])),
                cpuPercent: Double(parts[3]),
                memPercent: Double(parts[4])
            )
        }
        return table
    }

    // MARK: - Views onto the snapshot

    public func uptimeSeconds(for pids: [Int32]) -> [Int32: Int] {
        var result: [Int32: Int] = [:]
        for pid in pids {
            if let seconds = entries[pid]?.uptimeSeconds { result[pid] = seconds }
        }
        return result
    }

    public func metrics(for pids: [Int32]) -> [Int32: ProcessMetricsResolver.Metrics] {
        var result: [Int32: ProcessMetricsResolver.Metrics] = [:]
        for pid in pids {
            guard let entry = entries[pid], let cpu = entry.cpuPercent, let mem = entry.memPercent else { continue }
            result[pid] = ProcessMetricsResolver.Metrics(cpuPercent: cpu, memPercent: mem)
        }
        return result
    }

    /// The (ppid, name) shape `ProcessTreeResolver.ancestry` expects.
    public var ancestryTable: [Int32: (ppid: Int32, name: String)] {
        entries.mapValues { ($0.ppid, $0.name) }
    }
}
