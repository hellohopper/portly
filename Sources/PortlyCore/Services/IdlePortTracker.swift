import Foundation

/// Decides which ports have gone quiet long enough to warrant an alert.
///
/// Extracted from PortStore so the rules -- particularly the branch that can kill a
/// user's process -- are testable without a live 30-minute wait.
public struct IdlePortTracker {

    /// Anything under this is noise (keepalives, health probes), not real traffic.
    public static let activityFloorBytesPerSecond: Double = 1024

    public struct Snapshot: Sendable, Equatable {
        /// Keyed by `pid-port`, not port alone: a fresh process reusing a port must
        /// start its own idle clock rather than inheriting the dead one's.
        public var lastActive: [String: TimeInterval]
        public var notified: Set<String>

        public init(lastActive: [String: TimeInterval] = [:], notified: Set<String> = []) {
            self.lastActive = lastActive
            self.notified = notified
        }
    }

    public let threshold: TimeInterval

    public init(threshold: TimeInterval = 30 * 60) {
        self.threshold = threshold
    }

    /// Advances the tracker.
    ///
    /// `now` is a *monotonic* timestamp (e.g. `ProcessInfo.systemUptime`), never a
    /// wall clock: with a wall clock, a laptop that sleeps overnight wakes up to find
    /// every port "idle for 15 hours" and — with auto-kill on — SIGTERMs every dev
    /// server the moment the lid opens.
    ///
    /// `hasThroughputData` reports whether throughput sampling is actually live. While
    /// it is false (nettop still warming up, or dead) nothing can be judged idle --
    /// absent data is not evidence of silence.
    public func advance(
        ports: [PortInfo],
        now: TimeInterval,
        hasThroughputData: Bool,
        state: Snapshot
    ) -> (state: Snapshot, idle: [PortInfo]) {
        var state = state
        let liveKeys = Set(ports.map(\.id))
        state.lastActive = state.lastActive.filter { liveKeys.contains($0.key) }
        state.notified.formIntersection(liveKeys)

        guard hasThroughputData else {
            // Reset every clock: the gap where sampling was unavailable says nothing
            // about whether these ports were busy.
            for info in ports { state.lastActive[info.id] = now }
            return (state, [])
        }

        var idle: [PortInfo] = []
        for info in ports where info.proto.contains("TCP") {
            let rate = (info.bytesInPerSecond ?? 0) + (info.bytesOutPerSecond ?? 0)
            let isActive = rate > Self.activityFloorBytesPerSecond

            guard !isActive, let lastActive = state.lastActive[info.id] else {
                state.lastActive[info.id] = now
                state.notified.remove(info.id)
                continue
            }
            // A clock that appears to run backwards (or absurdly far forward) means the
            // monotonic source was reset; re-arm rather than firing on a bogus delta.
            let elapsed = now - lastActive
            guard elapsed >= 0 else {
                state.lastActive[info.id] = now
                continue
            }
            guard elapsed >= threshold, !state.notified.contains(info.id) else { continue }

            state.notified.insert(info.id)
            idle.append(info)
        }
        return (state, idle)
    }
}
