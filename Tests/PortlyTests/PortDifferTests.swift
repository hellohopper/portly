import Testing
@testable import Portly

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
}
