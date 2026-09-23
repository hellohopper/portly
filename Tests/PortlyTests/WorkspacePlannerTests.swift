import Testing
@testable import PortlyCore

struct WorkspacePlannerTests {
    typealias Service = ProjectConfigResolver.Service

    @Test func independentServicesStartTogetherInNameOrder() throws {
        let waves = try WorkspacePlanner.waves(["web": Service(command: "a"), "api": Service(command: "b")])
        #expect(waves == [["api", "web"]])
    }

    @Test func dependenciesStartInEarlierWaves() throws {
        let services = [
            "db": Service(command: "db"),
            "api": Service(command: "api", port: 8000, dependsOn: ["db"]),
            "worker": Service(command: "worker", dependsOn: ["db"]),
            "web": Service(command: "web", port: 3000, dependsOn: ["api"]),
        ]
        #expect(try WorkspacePlanner.waves(services) == [["db"], ["api", "worker"], ["web"]])
        #expect(WorkspacePlanner.dependedOn(services) == ["db", "api"])
    }

    @Test func rejectsUnknownDependencies() {
        #expect(throws: WorkspacePlanner.PlanError.unknownDependency(service: "web", dependency: "api")) {
            try WorkspacePlanner.waves(["web": Service(command: "web", dependsOn: ["api"])])
        }
    }

    @Test func rejectsCycles() {
        let services = [
            "a": Service(command: "a", dependsOn: ["b"]),
            "b": Service(command: "b", dependsOn: ["a"]),
            "c": Service(command: "c"),
        ]
        #expect(throws: WorkspacePlanner.PlanError.cycle(["a", "b"])) {
            try WorkspacePlanner.waves(services)
        }
    }
}
