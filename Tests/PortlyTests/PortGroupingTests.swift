import Testing
@testable import Portly

struct PortGroupingTests {

    private func makeInfo(port: Int, projectName: String? = nil) -> PortInfo {
        PortInfo(pid: 100, port: port, proto: "TCP", processName: "node", commandPath: nil, projectName: projectName)
    }

    @Test func pinnedPortsFormTheirOwnSectionFirst() {
        let ports = [
            makeInfo(port: 3000, projectName: "web"),
            makeInfo(port: 8000, projectName: "api")
        ]

        let sections = PortGrouping.sections(for: ports, pinned: [8000])

        #expect(sections.first?.title == "Pinned")
        #expect(sections.first?.ports.map(\.port) == [8000])
    }

    @Test func groupsRemainingPortsByProjectAlphabetically() {
        let ports = [
            makeInfo(port: 3000, projectName: "web"),
            makeInfo(port: 8000, projectName: "api"),
            makeInfo(port: 9000, projectName: "web")
        ]

        let sections = PortGrouping.sections(for: ports, pinned: [])

        #expect(sections.map(\.title) == ["api", "web"])
        #expect(sections.last?.ports.map(\.port) == [3000, 9000])
    }

    @Test func portsWithoutProjectGoToOtherLast() {
        let ports = [
            makeInfo(port: 3000, projectName: nil),
            makeInfo(port: 8000, projectName: "api")
        ]

        let sections = PortGrouping.sections(for: ports, pinned: [])

        #expect(sections.map(\.title) == ["api", "Other"])
    }

    @Test func noSectionsWhenNoPorts() {
        #expect(PortGrouping.sections(for: [], pinned: []).isEmpty)
    }
}
