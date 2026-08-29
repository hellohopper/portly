import Foundation

/// Tracks live network throughput (bytes/sec in and out) per pid.
///
/// `nettop` takes roughly 4-5s just to start up, so re-launching it on every 2s port-list
/// refresh (like the other `ps`-based resolvers do) isn't viable. Instead this keeps a
/// single `nettop -d` (delta mode, continuous logging) process running for the app's
/// lifetime and re-parses each new sample block as it streams in.
public final class NetworkThroughputResolver: @unchecked Sendable {
    public static let shared = NetworkThroughputResolver()

    public struct Throughput: Sendable {
        public let bytesInPerSecond: Double
        public let bytesOutPerSecond: Double
    }

    private let sampleIntervalSeconds: Double = 2
    private let lock = NSLock()

    private var process: Process?
    /// Retained so the readability handler can be detached on teardown -- otherwise it
    /// keeps firing against a dead process.
    private var readHandle: FileHandle?
    private var latest: [Int32: Throughput] = [:]
    /// Recent combined (in+out) samples per pid, oldest first, capped for a sparkline.
    private var history: [Int32: [Double]] = [:]
    private let historyLimit = 20

    // Only touched from the pipe's readabilityHandler, which macOS serializes onto a
    // single dispatch queue per file handle, so these don't need the lock.
    private var currentBlock: [Int32: Throughput] = [:]
    private var isFirstBlock = true
    private var lineBuffer = ""

    private init() {}

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard process == nil else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = [
            "-P", "-d", "-x", "-l", "0",
            "-s", String(Int(sampleIntervalSeconds)),
            "-J", "bytes_in,bytes_out"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // Empty data means EOF: nettop exited or was killed. Foundation would
            // otherwise keep re-invoking this handler in a tight loop, burning a core
            // for the rest of the app's lifetime -- so tear down and allow a respawn.
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                self?.handleUnexpectedExit()
                return
            }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            self?.consume(chunk)
        }

        do {
            try task.run()
            process = task
            readHandle = pipe.fileHandleForReading
        } catch {
            process = nil
            readHandle = nil
        }
    }

    public func stop() {
        lock.lock()
        let taskToStop = process
        readHandle?.readabilityHandler = nil
        readHandle = nil
        process = nil
        // A later start() must not treat nettop's cumulative first block as a delta,
        // and must not resume mid-line from the previous run.
        isFirstBlock = true
        lineBuffer = ""
        currentBlock = [:]
        latest = [:]
        history = [:]
        lock.unlock()
        taskToStop?.terminate()
    }

    /// nettop died on its own. Clear the process handle so the next `start()` can
    /// respawn it rather than the guard silently keeping throughput frozen forever.
    private func handleUnexpectedExit() {
        lock.lock()
        let taskToStop = process
        readHandle = nil
        process = nil
        isFirstBlock = true
        lineBuffer = ""
        currentBlock = [:]
        lock.unlock()
        taskToStop?.terminate()
    }

    /// True when nettop is not currently running, so a supervisor can restart it.
    public var needsRestart: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process == nil
    }

    /// Whether throughput sampling has actually produced a reading yet. Callers that
    /// infer *inactivity* from a zero rate must check this first: no samples means no
    /// data, which is not the same as no traffic.
    public var hasSamples: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !latest.isEmpty
    }

    public func throughput(for pid: Int32) -> Throughput? {
        lock.lock()
        defer { lock.unlock() }
        return latest[pid]
    }

    /// Oldest-first combined bytes/sec samples for a sparkline, most recent
    /// `historyLimit` blocks. Empty until at least one non-baseline block has landed.
    public func history(for pid: Int32) -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        return history[pid] ?? []
    }

    private func consume(_ chunk: String) {
        lineBuffer += chunk
        var lines = lineBuffer.components(separatedBy: "\n")
        lineBuffer = lines.removeLast() // may be a partial line; keep it for the next chunk

        for line in lines {
            if NettopLineParser.isHeaderLine(line) {
                finishBlock()
                continue
            }
            if let sample = NettopLineParser.parseDataLine(line) {
                currentBlock[sample.pid] = Throughput(
                    bytesInPerSecond: sample.bytesIn / sampleIntervalSeconds,
                    bytesOutPerSecond: sample.bytesOut / sampleIntervalSeconds
                )
            }
        }
    }

    private func finishBlock() {
        defer { currentBlock = [:] }
        guard !currentBlock.isEmpty else { return }

        if isFirstBlock {
            // The first block after starting logging mode is a cumulative baseline
            // (bytes since each process started), not a delta -- discard it rather
            // than showing a bogus multi-gigabyte "rate".
            isFirstBlock = false
            return
        }

        lock.lock()
        latest = currentBlock
        for (pid, sample) in currentBlock {
            var samples = history[pid] ?? []
            samples.append(sample.bytesInPerSecond + sample.bytesOutPerSecond)
            if samples.count > historyLimit {
                samples.removeFirst(samples.count - historyLimit)
            }
            history[pid] = samples
        }
        let livePids = Set(currentBlock.keys)
        history = history.filter { livePids.contains($0.key) }
        lock.unlock()
    }
}
