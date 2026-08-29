import Testing
import Foundation
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
}
