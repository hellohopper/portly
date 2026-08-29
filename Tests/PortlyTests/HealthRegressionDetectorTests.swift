import Testing
@testable import PortlyCore

struct HealthRegressionDetectorTests {

    @Test func reportsATransitionIntoFailing() {
        let result = HealthRegressionDetector.regressions(old: [3000: 200], new: [3000: 500], pinned: [3000])
        #expect(result == [3000])
    }

    @Test func ignoresPortsThatWereAlreadyFailing() {
        let result = HealthRegressionDetector.regressions(old: [3000: 503], new: [3000: 500], pinned: [3000])
        #expect(result.isEmpty)
    }

    @Test func ignoresPortsWithNoPriorReading() {
        // Otherwise every app launch would alert for anything already broken.
        let result = HealthRegressionDetector.regressions(old: [:], new: [3000: 500], pinned: [3000])
        #expect(result.isEmpty)
    }

    @Test func ignoresUnpinnedPorts() {
        let result = HealthRegressionDetector.regressions(old: [3000: 200], new: [3000: 500], pinned: [])
        #expect(result.isEmpty)
    }

    @Test func ignoresRecoveryAndClientErrors() {
        #expect(HealthRegressionDetector.regressions(old: [3000: 500], new: [3000: 200], pinned: [3000]).isEmpty)
        #expect(HealthRegressionDetector.regressions(old: [3000: 200], new: [3000: 404], pinned: [3000]).isEmpty)
    }

    @Test func reportsEveryRegressedPort() {
        let result = HealthRegressionDetector.regressions(
            old: [3000: 200, 8080: 200],
            new: [3000: 500, 8080: 502],
            pinned: [3000, 8080]
        )
        #expect(result == [3000, 8080])
    }
}
