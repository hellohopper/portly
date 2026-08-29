import Testing
@testable import PortlyCore

struct IdlePortTrackerTests {

    private let threshold: Double = 1800

    private func port(_ number: Int, pid: Int32 = 100, bytes: Double = 0, proto: String = "TCP") -> PortInfo {
        var info = PortInfo(pid: pid, port: number, proto: proto, processName: "node", commandPath: nil)
        info.bytesInPerSecond = bytes
        info.bytesOutPerSecond = 0
        return info
    }

    @Test func reportsNothingBeforeTheThreshold() {
        let tracker = IdlePortTracker(threshold: threshold)
        let first = tracker.advance(ports: [port(3000)], now: 0, hasThroughputData: true, state: .init())
        #expect(first.idle.isEmpty)

        let later = tracker.advance(ports: [port(3000)], now: threshold - 1, hasThroughputData: true, state: first.state)
        #expect(later.idle.isEmpty)
    }

    @Test func reportsAPortIdlePastTheThreshold() {
        let tracker = IdlePortTracker(threshold: threshold)
        let first = tracker.advance(ports: [port(3000)], now: 0, hasThroughputData: true, state: .init())
        let result = tracker.advance(ports: [port(3000)], now: threshold, hasThroughputData: true, state: first.state)
        #expect(result.idle.map(\.port) == [3000])
    }

    @Test func reportsEachIdleStretchOnlyOnce() {
        let tracker = IdlePortTracker(threshold: threshold)
        var state = tracker.advance(ports: [port(3000)], now: 0, hasThroughputData: true, state: .init()).state
        let fired = tracker.advance(ports: [port(3000)], now: threshold, hasThroughputData: true, state: state)
        #expect(fired.idle.count == 1)
        state = fired.state

        let again = tracker.advance(ports: [port(3000)], now: threshold + 10, hasThroughputData: true, state: state)
        #expect(again.idle.isEmpty)
    }

    @Test func trafficReArmsTheAlert() {
        let tracker = IdlePortTracker(threshold: threshold)
        var state = tracker.advance(ports: [port(3000)], now: 0, hasThroughputData: true, state: .init()).state
        state = tracker.advance(ports: [port(3000)], now: threshold, hasThroughputData: true, state: state).state

        // Busy again...
        state = tracker.advance(
            ports: [port(3000, bytes: 50_000)], now: threshold + 10, hasThroughputData: true, state: state
        ).state
        // ...then quiet for another full stretch.
        let refired = tracker.advance(
            ports: [port(3000)], now: threshold * 2 + 20, hasThroughputData: true, state: state
        )
        #expect(refired.idle.map(\.port) == [3000])
    }

    /// The sleep/wake regression: with a wall clock and no samples, every port looked
    /// idle for hours the instant the lid opened -- and auto-kill acted on it.
    @Test func absentThroughputDataNeverCountsAsIdle() {
        let tracker = IdlePortTracker(threshold: threshold)
        let first = tracker.advance(ports: [port(3000)], now: 0, hasThroughputData: true, state: .init())

        // Long gap with sampling unavailable (asleep), then it comes back.
        let afterWake = tracker.advance(
            ports: [port(3000)], now: 50_000, hasThroughputData: false, state: first.state
        )
        #expect(afterWake.idle.isEmpty)

        // The clock restarts from the wake, so nothing fires immediately afterwards.
        let justAfter = tracker.advance(
            ports: [port(3000)], now: 50_001, hasThroughputData: true, state: afterWake.state
        )
        #expect(justAfter.idle.isEmpty)
    }

    /// A new process on a recycled port must not inherit the dead one's idle clock.
    @Test func aNewProcessOnTheSamePortStartsItsOwnClock() {
        let tracker = IdlePortTracker(threshold: threshold)
        let old = port(3000, pid: 111)
        var state = tracker.advance(ports: [old], now: 0, hasThroughputData: true, state: .init()).state

        // Just before the threshold, a different process takes over the port.
        let replacement = port(3000, pid: 222)
        state = tracker.advance(
            ports: [replacement], now: threshold - 1, hasThroughputData: true, state: state
        ).state

        let atOldThreshold = tracker.advance(
            ports: [replacement], now: threshold, hasThroughputData: true, state: state
        )
        #expect(atOldThreshold.idle.isEmpty)
    }

    @Test func ignoresUDPPorts() {
        let tracker = IdlePortTracker(threshold: threshold)
        let udp = port(5353, proto: "UDP")
        let first = tracker.advance(ports: [udp], now: 0, hasThroughputData: true, state: .init())
        let later = tracker.advance(ports: [udp], now: threshold * 2, hasThroughputData: true, state: first.state)
        #expect(later.idle.isEmpty)
    }

    @Test func lowRateTrafficStillCountsAsIdle() {
        let tracker = IdlePortTracker(threshold: threshold)
        let trickle = port(3000, bytes: 100) // below the 1KB/s floor
        let first = tracker.advance(ports: [trickle], now: 0, hasThroughputData: true, state: .init())
        let later = tracker.advance(ports: [trickle], now: threshold, hasThroughputData: true, state: first.state)
        #expect(later.idle.map(\.port) == [3000])
    }

    @Test func forgetsPortsThatDisappear() {
        let tracker = IdlePortTracker(threshold: threshold)
        let first = tracker.advance(ports: [port(3000)], now: 0, hasThroughputData: true, state: .init())
        let gone = tracker.advance(ports: [], now: 10, hasThroughputData: true, state: first.state)
        #expect(gone.state.lastActive.isEmpty)
        #expect(gone.state.notified.isEmpty)
    }
}
