import Testing
import Foundation
@testable import PortlyCore

struct ProjectConfigExporterTests {

    private func info(port: Int, workingDirectory: String?) -> PortInfo {
        var info = PortInfo(pid: 1, port: port, proto: "TCP", processName: "node", commandPath: nil)
        info.workingDirectory = workingDirectory
        return info
    }

    // MARK: - merge

    /// The documented precedence: manual labels win, but entries the file already had
    /// for ports that aren't currently listening must survive.
    @Test func manualLabelsWinAndExistingEntriesSurvive() {
        let merged = ProjectConfigExporter.merge(
            existing: [3000: "old name", 8080: "api"],
            manual: [3000: "new name"]
        )
        #expect(merged[3000] == "new name")
        #expect(merged[8080] == "api")
    }

    @Test func mergeAddsNewPorts() {
        let merged = ProjectConfigExporter.merge(existing: [:], manual: [3000: "web"])
        #expect(merged == [3000: "web"])
    }

    // MARK: - encode

    @Test func encodesUnderALabelsKeyWithStringPorts() throws {
        let data = try #require(ProjectConfigExporter.encode(labels: [3000: "web"]))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let labels = try #require(json["labels"] as? [String: String])
        #expect(labels == ["3000": "web"])
    }

    /// Round-trips through the reader, so export and import can't drift apart.
    @Test func encodedOutputIsReadableByTheResolver() throws {
        let data = try #require(ProjectConfigExporter.encode(labels: [3000: "web", 8080: "api"]))
        #expect(ProjectConfigResolver.parse(data).labels == [3000: "web", 8080: "api"])
    }

    // MARK: - exportableProjects

    @Test func groupsLabelledPortsByProjectRoot() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("portly-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projects = ProjectConfigExporter.exportableProjects(
            ports: [info(port: 3000, workingDirectory: root.path)],
            manualLabels: [3000: "web"]
        )
        #expect(projects.count == 1)
        #expect(projects[0].labels == [3000: "web"])
    }

    @Test func skipsPortsWithNoManualLabel() {
        let projects = ProjectConfigExporter.exportableProjects(
            ports: [info(port: 3000, workingDirectory: "/tmp")],
            manualLabels: [:]
        )
        #expect(projects.isEmpty)
    }

    @Test func skipsPortsWithNoWorkingDirectory() {
        let projects = ProjectConfigExporter.exportableProjects(
            ports: [info(port: 3000, workingDirectory: nil)],
            manualLabels: [3000: "web"]
        )
        #expect(projects.isEmpty)
    }
}
