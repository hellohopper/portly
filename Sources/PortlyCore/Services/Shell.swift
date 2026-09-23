import Foundation

/// Runs a short-lived helper process and captures its stdout.
///
/// Every call site used to hand `Process` an unread `standardError` pipe. That
/// deadlocks: a child that writes more than the ~64KB pipe buffer to stderr (e.g.
/// `lsof` warning about each unreachable network mount) blocks forever, never closes
/// stdout, and the reader blocks with it. Here stderr is drained concurrently with
/// stdout, and a timeout terminates a child that wedges anyway -- without one, a
/// single hung `lsof` freezes the whole port list permanently.
public enum Shell {

    /// Lets the reader closure hand its result back across queues without tripping
    /// the concurrency checker on a captured `var`.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Data?

        func setOut(_ data: Data) {
            lock.lock()
            value = data
            lock.unlock()
        }

        var out: Data? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    /// Captured stdout, or nil if the process couldn't be launched, timed out, or
    /// produced output that isn't UTF-8.
    public static func run(
        _ path: String,
        _ arguments: [String],
        timeout: TimeInterval = 5
    ) -> String? {
        execute(path, arguments, timeout: timeout)?.output
    }

    /// Runs a process only for its exit status, discarding output. Success means a
    /// zero exit: stdout alone can't tell, since a failing command usually prints
    /// nothing to stdout, which reads as an empty (non-nil) string.
    @discardableResult
    public static func succeeds(
        _ path: String,
        _ arguments: [String],
        timeout: TimeInterval = 5
    ) -> Bool {
        execute(path, arguments, timeout: timeout)?.status == 0
    }

    /// Stdout plus exit status, or nil if the process couldn't be launched or timed out.
    static func execute(
        _ path: String,
        _ arguments: [String],
        timeout: TimeInterval
    ) -> (output: String?, status: Int32)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        // Never share the caller's stdin: the CLI runs attached to a terminal, and an
        // interactive child (e.g. `zsh -i` reading PATH) would contend for it.
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Read both pipes concurrently. Draining stderr is not optional: it is the
        // difference between "the child finishes" and "the child blocks on a full
        // stderr buffer forever".
        let collected = Collector()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "dev.hellohopper.portly.shell", attributes: .concurrent)

        queue.async(group: group) { collected.setOut(outPipe.fileHandleForReading.readDataToEndOfFile()) }
        // stderr is read purely to drain it; the content is discarded.
        queue.async(group: group) { _ = errPipe.fileHandleForReading.readDataToEndOfFile() }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            // Terminating closes the child's pipe ends, which unblocks both readers.
            process.terminate()
            _ = group.wait(timeout: .now() + 1)
            // A child that ignores SIGTERM would otherwise hang waitUntilExit below.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return nil
        }

        process.waitUntilExit()
        return (collected.out.flatMap { String(data: $0, encoding: .utf8) }, process.terminationStatus)
    }
}
