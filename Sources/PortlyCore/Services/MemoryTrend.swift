import Foundation

/// Rolling per-process memory samples, and a judgement on whether they describe a
/// leak rather than normal churn. A dev server that creeps from 300MB to 2GB over
/// an afternoon is invisible in a single %MEM reading.
public struct MemoryTrend: Sendable, Equatable {

    public static let sampleLimit = 30

    private(set) var samples: [Int32: [Double]] = [:]

    public init() {}

    /// Appends this refresh's reading per pid and forgets pids that are gone.
    public mutating func record(_ residentBytes: [Int32: UInt64]) {
        samples = samples.filter { residentBytes[$0.key] != nil }
        for (pid, bytes) in residentBytes {
            var history = samples[pid] ?? []
            history.append(Double(bytes))
            if history.count > Self.sampleLimit {
                history.removeFirst(history.count - Self.sampleLimit)
            }
            samples[pid] = history
        }
    }

    public func history(for pid: Int32) -> [Double] {
        samples[pid] ?? []
    }

    /// Sustained growth: enough samples to mean something, at least 50% up from the
    /// start of the window, and rising in the large majority of steps (a server that
    /// allocates and frees in a sawtooth isn't leaking).
    public static func isGrowing(_ history: [Double]) -> Bool {
        guard history.count >= 8, let first = history.first, let last = history.last, first > 0 else { return false }
        guard last >= first * 1.5 else { return false }
        let steps = zip(history, history.dropFirst())
        let rising = steps.filter { $1 >= $0 }.count
        return Double(rising) / Double(history.count - 1) >= 0.8
    }
}
