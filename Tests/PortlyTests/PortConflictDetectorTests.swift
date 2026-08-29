import Testing
import Foundation
@testable import PortlyCore

struct PortConflictDetectorTests {

    private func info(port: Int, pid: Int32 = 100, project: String? = "web") -> PortInfo {
        var info = PortInfo(pid: pid, port: port, proto: "TCP", processName: "node", commandPath: nil)
        info.projectName = project
        return info
    }

    private func config(labels: [Int: String]) -> ProjectConfigResolver.Config {
        var config = ProjectConfigResolver.Config()
        config.labels = labels
        config.expectedPorts = Set(labels.keys)
        return config
    }

    @Test func flagsAPortHeldByAnotherProject() {
        let conflicts = PortConflictDetector.conflicts(
            configsByProjectRoot: ["/repos/web": config(labels: [3000: "frontend"])],
            projectRootByPort: [3000: "/repos/admin"],
            ports: [info(port: 3000, pid: 4821, project: "admin")]
        )
        #expect(conflicts.count == 1)
        #expect(conflicts[0].port == 3000)
        #expect(conflicts[0].expectedBy == "web")
        #expect(conflicts[0].expectedLabel == "frontend")
        #expect(conflicts[0].heldBy.pid == 4821)
    }

    @Test func staysQuietWhenTheDeclaringProjectHoldsIt() {
        let conflicts = PortConflictDetector.conflicts(
            configsByProjectRoot: ["/repos/web": config(labels: [3000: "frontend"])],
            projectRootByPort: [3000: "/repos/web"],
            ports: [info(port: 3000)]
        )
        #expect(conflicts.isEmpty)
    }

    /// A declared port nothing is listening on isn't a conflict -- that server just
    /// hasn't been started yet.
    @Test func staysQuietWhenThePortIsFree() {
        let conflicts = PortConflictDetector.conflicts(
            configsByProjectRoot: ["/repos/web": config(labels: [3000: "frontend"])],
            projectRootByPort: [:],
            ports: []
        )
        #expect(conflicts.isEmpty)
    }

    @Test func ignoresPortsNobodyDeclared() {
        let conflicts = PortConflictDetector.conflicts(
            configsByProjectRoot: ["/repos/web": config(labels: [3000: "frontend"])],
            projectRootByPort: [8080: "/repos/other"],
            ports: [info(port: 8080, project: "other")]
        )
        #expect(conflicts.isEmpty)
    }

    @Test func sortsByPort() {
        let conflicts = PortConflictDetector.conflicts(
            configsByProjectRoot: ["/repos/web": config(labels: [8080: "api", 3000: "frontend"])],
            projectRootByPort: [3000: "/x", 8080: "/x"],
            ports: [info(port: 8080, project: "x"), info(port: 3000, project: "x")]
        )
        #expect(conflicts.map(\.port) == [3000, 8080])
    }
}
