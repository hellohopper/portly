import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// SIGTERM with a deadline.
///
/// Restart used to SIGTERM and relaunch after a fixed 0.5s. A dev server that takes
/// longer to shut down gracefully (Next.js, anything draining connections) still held
/// the port, so the new copy failed with EADDRINUSE -- or, worse, Vite quietly moved
/// to 5174. This waits for the process to really be gone, escalating to SIGKILL if
/// it ignores the polite request.
public enum ProcessTerminator {

    /// Whether `pid` is a live (non-zombie) process. A zombie has already released
    /// its sockets; it's only waiting for its parent to reap it.
    public static func isAlive(_ pid: Int32) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            // Can't inspect it (another user's process); kill(0) said it exists.
            return true
        }
        return info.pbi_status != UInt32(SZOMB)
    }

    /// Polls until every pid has exited or `timeout` passes. True when all are gone.
    public static func waitForExit(
        _ pids: [Int32],
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.05
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if !pids.contains(where: isAlive) { return true }
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    public enum Outcome: Sendable, Equatable {
        /// Every process exited after SIGTERM.
        case terminated
        /// At least one ignored SIGTERM past the grace period and was SIGKILLed.
        case killed
        /// Something survived even SIGKILL (e.g. stuck in uninterruptible I/O, or not ours to signal).
        case survived
    }

    /// SIGTERM, wait up to `grace`, then SIGKILL whatever is left (when `escalate`).
    public static func terminate(
        _ pids: [Int32],
        grace: TimeInterval = 5,
        escalate: Bool = true
    ) async -> Outcome {
        let targets = Array(Set(pids))
        guard !targets.isEmpty else { return .terminated }
        for pid in targets { kill(pid, SIGTERM) }
        if await waitForExit(targets, timeout: grace) { return .terminated }
        guard escalate else { return .survived }

        let stubborn = targets.filter(isAlive)
        for pid in stubborn { kill(pid, SIGKILL) }
        return await waitForExit(stubborn, timeout: 2) ? .killed : .survived
    }

    /// Blocking variant for the synchronous CLI.
    public static func terminateBlocking(
        _ pids: [Int32],
        grace: TimeInterval = 5,
        escalate: Bool = true
    ) -> Outcome {
        let semaphore = DispatchSemaphore(value: 0)
        let box = OutcomeBox()
        Task.detached {
            box.value = await terminate(pids, grace: grace, escalate: escalate)
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }

    private final class OutcomeBox: @unchecked Sendable {
        var value: Outcome = .survived
    }
}
