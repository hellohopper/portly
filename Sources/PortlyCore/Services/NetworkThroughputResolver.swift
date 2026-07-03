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
    private var latest: [Int32: Throughput] = [:]

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
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            self?.consume(chunk)
        }

        do {
            try task.run()
            process = task
        } catch {
            process = nil
        }
    }

    public func stop() {
        lock.lock()
        let taskToStop = process
        process = nil
        lock.unlock()
        taskToStop?.terminate()
    }

    public func throughput(for pid: Int32) -> Throughput? {
        lock.lock()
        defer { lock.unlock() }
        return latest[pid]
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
        lock.unlock()
    }
}
