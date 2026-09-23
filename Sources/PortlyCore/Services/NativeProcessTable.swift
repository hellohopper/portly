import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Builds a `ProcessTable` from the kernel instead of `ps`: `sysctl(KERN_PROC_ALL)`
/// for the parent/name/start-time table, `PROC_PIDTASKINFO` for CPU time and
/// resident memory. With the socket scan already native, this was the last helper
/// process spawned on every refresh.
///
/// %CPU is measured, not reported: the kernel exposes cumulative CPU time, so each
/// snapshot compares against the previous one. A process's first appearance has no
/// %CPU yet (ps's figure was a decaying average, which the delta over the refresh
/// interval replaces with something closer to "right now").
enum NativeProcessTable {

    /// nil when the process list can't be read, so the caller can fall back to ps.
    static func snapshot(now: Date = Date()) -> ProcessTable? {
        guard let processes = allProcesses() else { return nil }
        let physicalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        var entries: [Int32: ProcessTable.Entry] = [:]
        var cpuTimes: [Int32: (start: TimeInterval, nanoseconds: UInt64)] = [:]

        for process in processes {
            let pid = process.kp_proc.p_pid
            let startTime = TimeInterval(process.kp_proc.p_starttime.tv_sec)
                + TimeInterval(process.kp_proc.p_starttime.tv_usec) / 1_000_000
            let task = taskInfo(pid)
            if let task {
                cpuTimes[pid] = (startTime, machToNanoseconds(task.pti_total_user &+ task.pti_total_system))
            }
            entries[pid] = ProcessTable.Entry(
                ppid: process.kp_eproc.e_ppid,
                name: name(of: pid, fallback: process),
                uptimeSeconds: max(0, Int(now.timeIntervalSince1970 - startTime)),
                cpuPercent: nil,
                memPercent: task.map { physicalMemory > 0 ? Double($0.pti_resident_size) / physicalMemory * 100 : 0 },
                residentBytes: task.map { UInt64($0.pti_resident_size) },
                startTime: startTime
            )
        }

        for (pid, percent) in CPUSampler.shared.percentages(for: cpuTimes, at: now) {
            guard let entry = entries[pid] else { continue }
            entries[pid] = entry.with(cpuPercent: percent)
        }
        return ProcessTable(entries: entries)
    }

    private static func allProcesses() -> [kinfo_proc]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        // The table can grow between the size query and the read; retry a few times.
        for _ in 0..<4 {
            var size = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
            size += size / 8
            var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
            var written = processes.count * MemoryLayout<kinfo_proc>.stride
            let result = processes.withUnsafeMutableBytes { buffer in
                sysctl(&mib, UInt32(mib.count), buffer.baseAddress, &written, nil, 0)
            }
            if result == 0 {
                return Array(processes.prefix(written / MemoryLayout<kinfo_proc>.stride))
            }
            guard errno == ENOMEM else { return nil }
        }
        return nil
    }

    private static func taskInfo(_ pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return info
    }

    /// The executable's name as `ps -o comm` reported it (its last path component):
    /// the kernel's 32-char name, falling back to the 16-char `p_comm`.
    private static func name(of pid: Int32, fallback process: kinfo_proc) -> String {
        var buffer = [UInt8](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
            return decodeCString(buffer)
        }
        let comm = withUnsafeBytes(of: process.kp_proc.p_comm) { Array($0) }
        return decodeCString(comm)
    }

    static func decodeCString(_ bytes: [UInt8]) -> String {
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// Task CPU times are in Mach absolute-time units, which are nanoseconds on Intel
    /// but not on Apple silicon (24MHz ticks), so they have to be scaled.
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(max(info.numer, 1)), UInt64(max(info.denom, 1)))
    }()

    static func machToNanoseconds(_ ticks: UInt64) -> UInt64 {
        ticks.multipliedReportingOverflow(by: timebase.numer).overflow
            ? ticks / timebase.denom * timebase.numer
            : ticks * timebase.numer / timebase.denom
    }
}

/// Remembers each process's cumulative CPU time from the previous snapshot, so the
/// next one can turn the difference into a percentage. Keyed on pid *and* start
/// time: a reused pid starts from zero rather than producing a huge negative delta.
final class CPUSampler: @unchecked Sendable {
    static let shared = CPUSampler()

    private let lock = NSLock()
    private var previous: [Int32: (start: TimeInterval, nanoseconds: UInt64, at: Date)] = [:]

    /// %CPU per pid over the time since the previous call (100 = one full core),
    /// omitting processes seen for the first time.
    func percentages(
        for samples: [Int32: (start: TimeInterval, nanoseconds: UInt64)],
        at now: Date
    ) -> [Int32: Double] {
        lock.lock()
        defer { lock.unlock() }
        var result: [Int32: Double] = [:]
        var next: [Int32: (start: TimeInterval, nanoseconds: UInt64, at: Date)] = [:]
        for (pid, sample) in samples {
            next[pid] = (sample.start, sample.nanoseconds, now)
            guard let last = previous[pid], last.start == sample.start,
                  sample.nanoseconds >= last.nanoseconds else { continue }
            let wall = now.timeIntervalSince(last.at)
            guard wall > 0.05 else { continue }
            result[pid] = Double(sample.nanoseconds - last.nanoseconds) / 1_000_000_000 / wall * 100
        }
        previous = next
        return result
    }
}
