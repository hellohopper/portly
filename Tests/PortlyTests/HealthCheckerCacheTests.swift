import Testing
import Foundation
import Network
@testable import PortlyCore

struct HealthCheckerCacheTests {

    /// Latency upgrades an otherwise-healthy result: a dev server's common real
    /// failure is a wedged 30-second response, not a dead socket.
    @Test func slowResponsesAreDistinguishedFromHealthyOnes() {
        #expect(HealthChecker.Category.classify(statusCode: 200, latency: 0.05) == .healthy)
        #expect(HealthChecker.Category.classify(statusCode: 200, latency: 5) == .slow)
    }

    @Test func latencyDoesNotMaskRealErrors() {
        #expect(HealthChecker.Category.classify(statusCode: 500, latency: 5) == .failing)
        #expect(HealthChecker.Category.classify(statusCode: 404, latency: 5) == .warning)
    }

    @Test func healthExposesItsOwnCategory() {
        #expect(HealthChecker.Health(statusCode: 200, latency: 0.01).category == .healthy)
        #expect(HealthChecker.Health(statusCode: 503, latency: 0.01).category == .failing)
    }

    @Test func targetsCompareByPathAndScheme() {
        #expect(HealthChecker.Target(path: "/") == HealthChecker.Target.default)
        #expect(HealthChecker.Target(path: "/health") != HealthChecker.Target.default)
        #expect(HealthChecker.Target(path: "/", useTLS: true) != HealthChecker.Target.default)
    }

    /// Probing a port nothing is listening on yields no entry (rather than a fake
    /// status), and the result is cached rather than re-probed on the next call.
    @Test func deadPortsYieldNoEntry() async {
        let checker = HealthChecker(recheckInterval: 60)
        let results = await checker.health(for: [64_999])
        #expect(results.isEmpty)
    }

    /// Ports that vanish from the list are evicted rather than lingering forever.
    @Test func dropsPortsThatAreNoLongerListed() async {
        let checker = HealthChecker(recheckInterval: 60)
        _ = await checker.health(for: [64_998, 64_999])
        let results = await checker.health(for: [64_998])
        #expect(results[64_999] == nil)
    }

    // MARK: - Backoff for ports that never answer

    @Test func answeringPortsUseTheBaseInterval() {
        #expect(HealthChecker.recheckDelay(base: 10, consecutiveMisses: 0) == 10)
        #expect(HealthChecker.recheckDelay(base: 10, consecutiveMisses: 1) == 10)
    }

    /// A non-HTTP port backs off 10 -> 20 -> 40 -> 60 and stays capped there, so a
    /// server that's merely slow to start still gets its badge within a minute.
    @Test func silentPortsBackOffUpToACap() {
        #expect(HealthChecker.recheckDelay(base: 10, consecutiveMisses: 2) == 20)
        #expect(HealthChecker.recheckDelay(base: 10, consecutiveMisses: 3) == 40)
        #expect(HealthChecker.recheckDelay(base: 10, consecutiveMisses: 4) == 60)
        #expect(HealthChecker.recheckDelay(base: 10, consecutiveMisses: 50) == 60)
    }

    // MARK: - TCP-only probing (databases and other wire-protocol services)

    @Test func tcpHealthHasNoStatusCodeAndIsHealthyWhenFast() {
        let health = HealthChecker.Health(kind: .tcp, latency: 0.01)
        #expect(health.statusCode == nil)
        #expect(health.category == .healthy)
    }

    @Test func tcpHealthIsSlowPastTheThreshold() {
        let health = HealthChecker.Health(kind: .tcp, latency: 5)
        #expect(health.category == .slow)
    }

    /// A port declared `tcpOnly` gets a raw TCP handshake probe instead of an HTTP
    /// request -- proven here against a bare TCP listener that would never answer HTTP.
    @Test func tcpOnlyPortsAreProbedByHandshakeNotHTTP() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            connection.cancel()
        }
        let ready = Ready()
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.start(queue: .global())
        await ready.wait()
        defer { listener.cancel() }

        let port = Int(listener.port!.rawValue)
        let checker = HealthChecker(recheckInterval: 60)
        let results = await checker.health(for: [port], tcpOnlyPorts: [port])

        let health = try #require(results[port])
        #expect(health.kind == .tcp)
        #expect(health.statusCode == nil)
    }
}

/// Bridges `NWListener`'s callback-based readiness into `async`/`await` for tests.
private final class Ready: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func signal() { semaphore.signal() }
    func wait() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.semaphore.wait()
                continuation.resume()
            }
        }
    }
}
