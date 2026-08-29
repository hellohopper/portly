import Testing
@testable import PortlyCore

struct PortLabelResolverTests {

    private func info(port: Int = 3000, processName: String = "node") -> PortInfo {
        PortInfo(pid: 1, port: port, proto: "TCP", processName: processName, commandPath: nil)
    }

    // MARK: - effectiveLabel

    /// The documented precedence: a manual label overrides the team's `.portly.json`.
    @Test func manualLabelWinsOverProjectConfig() {
        let label = PortLabelResolver.effectiveLabel(
            for: 3000, manual: [3000: "mine"], fromConfig: [3000: "theirs"]
        )
        #expect(label == "mine")
    }

    @Test func fallsBackToProjectConfig() {
        let label = PortLabelResolver.effectiveLabel(
            for: 3000, manual: [:], fromConfig: [3000: "theirs"]
        )
        #expect(label == "theirs")
    }

    @Test func returnsNilWhenNeitherSourceHasOne() {
        #expect(PortLabelResolver.effectiveLabel(for: 3000, manual: [:], fromConfig: [:]) == nil)
    }

    /// A manual label for a *different* port must not leak across.
    @Test func labelsAreScopedToTheirPort() {
        let label = PortLabelResolver.effectiveLabel(
            for: 3000, manual: [8080: "other"], fromConfig: [:]
        )
        #expect(label == nil)
    }

    // MARK: - matches

    @Test func emptyNeedleMatchesEverything() {
        #expect(PortLabelResolver.matches(info(), needle: "", manual: [:], fromConfig: [:]))
    }

    @Test func matchesOnTheUnderlyingPortInfo() {
        #expect(PortLabelResolver.matches(info(), needle: "node", manual: [:], fromConfig: [:]))
        #expect(PortLabelResolver.matches(info(), needle: "3000", manual: [:], fromConfig: [:]))
    }

    /// Labels are keyed by port rather than living on PortInfo, so without this extra
    /// check they'd be invisible to the search field.
    @Test func matchesOnAManualLabel() {
        #expect(PortLabelResolver.matches(
            info(), needle: "staging", manual: [3000: "staging API"], fromConfig: [:]
        ))
    }

    @Test func matchesOnAProjectConfigLabel() {
        #expect(PortLabelResolver.matches(
            info(), needle: "frontend", manual: [:], fromConfig: [3000: "web frontend"]
        ))
    }

    @Test func labelMatchingIsCaseInsensitive() {
        #expect(PortLabelResolver.matches(
            info(), needle: "staging", manual: [3000: "STAGING API"], fromConfig: [:]
        ))
    }

    /// The overridden label is the one that's searchable -- searching for the config
    /// label a manual one replaced should not find the row.
    @Test func onlyTheEffectiveLabelIsSearchable() {
        #expect(!PortLabelResolver.matches(
            info(), needle: "theirs", manual: [3000: "mine"], fromConfig: [3000: "theirs"]
        ))
    }

    @Test func rejectsRowsThatMatchNothing() {
        #expect(!PortLabelResolver.matches(
            info(), needle: "postgres", manual: [3000: "web"], fromConfig: [:]
        ))
    }
}
