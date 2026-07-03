import Testing
@testable import PortlyCore

struct UpdateCheckerTests {

    @Test func newerPatchVersionIsDetected() {
        #expect(UpdateChecker.isVersion("0.1.1", newerThan: "0.1.0"))
    }

    @Test func sameVersionIsNotNewer() {
        #expect(!UpdateChecker.isVersion("0.1.0", newerThan: "0.1.0"))
    }

    @Test func olderVersionIsNotNewer() {
        #expect(!UpdateChecker.isVersion("0.1.0", newerThan: "0.2.0"))
    }

    @Test func numericComparisonBeatsStringComparison() {
        // "0.9.0" < "0.10.0" numerically, but ">" as plain strings -- must compare
        // per-component as integers, not lexicographically.
        #expect(UpdateChecker.isVersion("0.10.0", newerThan: "0.9.0"))
        #expect(!UpdateChecker.isVersion("0.9.0", newerThan: "0.10.0"))
    }

    @Test func differingComponentCountsAreHandled() {
        #expect(UpdateChecker.isVersion("1.0", newerThan: "0.9.9"))
        #expect(!UpdateChecker.isVersion("0.9", newerThan: "0.9.1"))
    }

    @Test func trailingZeroComponentsAreEquivalent() {
        // "0.4" and "0.4.0" are the same version; neither is newer.
        #expect(!UpdateChecker.isVersion("0.4", newerThan: "0.4.0"))
        #expect(!UpdateChecker.isVersion("0.4.0", newerThan: "0.4"))
    }
}
