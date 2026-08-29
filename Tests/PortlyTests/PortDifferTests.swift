import Testing
@testable import PortlyCore

struct PortDifferTests {

    private func makeInfo(port: Int) -> PortInfo {
        PortInfo(pid: 100, port: port, proto: "TCP", processName: "node", commandPath: nil)
    }

    @Test func detectsNewlyAppearedPorts() {
        let old = [makeInfo(port: 3000)]
        let new = [makeInfo(port: 3000), makeInfo(port: 8000)]

        let diff = PortDiffer.diff(old: old, new: new, pinned: [])

        #expect(diff.newPorts.map(\.port) == [8000])
        #expect(diff.deadPinnedPorts.isEmpty)
    }

    @Test func detectsDeadPinnedPorts() {
        let old = [makeInfo(port: 3000), makeInfo(port: 8000)]
        let new = [makeInfo(port: 3000)]

        let diff = PortDiffer.diff(old: old, new: new, pinned: [8000])

        #expect(diff.deadPinnedPorts.map(\.port) == [8000])
        #expect(diff.newPorts.isEmpty)
    }

    @Test func doesNotFlagUnpinnedPortsThatDisappear() {
        let old = [makeInfo(port: 3000), makeInfo(port: 8000)]
        let new = [makeInfo(port: 3000)]

        let diff = PortDiffer.diff(old: old, new: new, pinned: [])

        #expect(diff.deadPinnedPorts.isEmpty)
    }

    @Test func noChangesWhenIdentical() {
        let ports = [makeInfo(port: 3000)]

        let diff = PortDiffer.diff(old: ports, new: ports, pinned: [3000])

        #expect(diff.newPorts.isEmpty)
        #expect(diff.deadPinnedPorts.isEmpty)
    }

    @Test func pinnedPortSurvivesPidChange() {
        // Diffing is by port number, so a dev-server restart (new pid, same port)
        // within one poll interval is neither "new" nor "died".
        let old = [PortInfo(pid: 100, port: 3000, proto: "TCP", processName: "node", commandPath: nil)]
        let new = [PortInfo(pid: 999, port: 3000, proto: "TCP", processName: "node", commandPath: nil)]

        let diff = PortDiffer.diff(old: old, new: new, pinned: [3000])

        #expect(diff.newPorts.isEmpty)
        #expect(diff.deadPinnedPorts.isEmpty)
    }

    /// ...but the handover must still be *visible*, or a crash-and-respawn leaves no
    /// trace in port history at all.
    @Test func reportsAPortThatChangedOwner() {
        let old = [PortInfo(pid: 100, port: 3000, proto: "TCP", processName: "node", commandPath: nil)]
        let new = [PortInfo(pid: 999, port: 3000, proto: "TCP", processName: "node", commandPath: nil)]

        let diff = PortDiffer.diff(old: old, new: new, pinned: [3000])

        #expect(diff.replacedPorts.map(\.pid) == [999])
    }

    @Test func doesNotReportReplacementWhenThePidIsUnchanged() {
        let ports = [makeInfo(port: 3000)]
        #expect(PortDiffer.diff(old: ports, new: ports, pinned: []).replacedPorts.isEmpty)
    }

    @Test func aBrandNewPortIsNotAReplacement() {
        let diff = PortDiffer.diff(old: [], new: [makeInfo(port: 3000)], pinned: [])
        #expect(diff.replacedPorts.isEmpty)
        #expect(diff.newPorts.map(\.port) == [3000])
    }

    /// Two processes sharing a port number (different local addresses) must not read
    /// as replacing each other every scan just because the list order shifted.
    @Test func aPortHeldByTwoProcessesDoesNotChurn() {
        let a = PortInfo(pid: 100, port: 3000, proto: "TCP", processName: "node", commandPath: nil)
        let b = PortInfo(pid: 200, port: 3000, proto: "TCP", processName: "node", commandPath: nil)

        #expect(PortDiffer.diff(old: [a, b], new: [b, a], pinned: []).replacedPorts.isEmpty)
    }

    @Test func everythingIsNewWhenOldIsEmpty() {
        let diff = PortDiffer.diff(old: [], new: [makeInfo(port: 3000)], pinned: [])
        #expect(diff.newPorts.map(\.port) == [3000])
    }

    @Test func closedPortsIncludeUnpinnedDisappearances() {
        let old = [makeInfo(port: 3000), makeInfo(port: 8000)]
        let new = [makeInfo(port: 3000)]

        let diff = PortDiffer.diff(old: old, new: new, pinned: [])

        #expect(diff.closedPorts.map(\.port) == [8000])
        #expect(diff.deadPinnedPorts.isEmpty)
    }

    @Test func deadPinnedPortsAreSubsetOfClosedPorts() {
        let old = [makeInfo(port: 3000), makeInfo(port: 8000)]
        let new: [PortInfo] = []

        let diff = PortDiffer.diff(old: old, new: new, pinned: [8000])

        #expect(diff.closedPorts.map(\.port) == [3000, 8000])
        #expect(diff.deadPinnedPorts.map(\.port) == [8000])
    }
}
