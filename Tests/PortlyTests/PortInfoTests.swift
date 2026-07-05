import Testing
@testable import PortlyCore

struct PortInfoTests {

    private func makeInfo(
        port: Int = 3000,
        processName: String = "node",
        projectName: String? = nil,
        gitBranch: String? = nil,
        frameworkLabel: String? = nil
    ) -> PortInfo {
        PortInfo(
            pid: 100, port: port, proto: "TCP", processName: processName, commandPath: nil,
            projectName: projectName, gitBranch: gitBranch, frameworkLabel: frameworkLabel
        )
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(makeInfo().matches(query: ""))
        #expect(makeInfo().matches(query: "   "))
    }

    @Test func matchesByPortNumber() {
        #expect(makeInfo(port: 5173).matches(query: "5173"))
        #expect(!makeInfo(port: 5173).matches(query: "3000"))
    }

    @Test func matchesByProcessNameCaseInsensitive() {
        #expect(makeInfo(processName: "Python3").matches(query: "python"))
    }

    @Test func matchesByProjectNameAndBranch() {
        let info = makeInfo(projectName: "portly-web", gitBranch: "feature/auth")
        #expect(info.matches(query: "portly"))
        #expect(info.matches(query: "auth"))
    }

    @Test func matchesByFrameworkLabel() {
        #expect(makeInfo(frameworkLabel: "Next.js").matches(query: "next"))
    }

    @Test func noMatchReturnsFalse() {
        let info = makeInfo(processName: "node", projectName: "portly-web")
        #expect(!info.matches(query: "django"))
    }

    @Test func idIsStableAcrossProtocolMerge() {
        // A row must keep its identity when TCP and UDP entries for the same
        // pid+port merge into "TCP+UDP" -- otherwise SwiftUI treats the merge as a
        // brand-new row, breaking animation and any in-progress keyboard focus.
        var info = makeInfo()
        let idBefore = info.id
        info.proto = "TCP+UDP"
        #expect(info.id == idBefore)
    }

    @Test func idDiffersAcrossPidOrPort() {
        let a = PortInfo(pid: 100, port: 3000, proto: "TCP", processName: "node", commandPath: nil)
        let b = PortInfo(pid: 200, port: 3000, proto: "TCP", processName: "node", commandPath: nil)
        let c = PortInfo(pid: 100, port: 4000, proto: "TCP", processName: "node", commandPath: nil)
        #expect(a.id != b.id)
        #expect(a.id != c.id)
    }
}
