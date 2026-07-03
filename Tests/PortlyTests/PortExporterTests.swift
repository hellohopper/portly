import Foundation
import Testing
@testable import PortlyCore

struct PortExporterTests {

    private func makePort(
        port: Int = 5173,
        processName: String = "node",
        frameworkLabel: String? = "Vite",
        projectName: String? = "portly-web",
        gitBranch: String? = "main"
    ) -> PortInfo {
        var info = PortInfo(pid: 4821, port: port, proto: "TCP", processName: processName, commandPath: nil)
        info.frameworkLabel = frameworkLabel
        info.projectName = projectName
        info.gitBranch = gitBranch
        return info
    }

    @Test func csvIncludesHeaderAndOneRowPerPort() {
        let data = PortExporter.export([makePort(), makePort(port: 3000)], format: .csv)
        let lines = String(data: data, encoding: .utf8)!.split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[0] == "port,proto,pid,processName,frameworkLabel,projectName,gitBranch")
        #expect(lines[1] == "5173,TCP,4821,node,Vite,portly-web,main")
    }

    @Test func csvEscapesFieldsContainingCommasAndQuotes() {
        let data = PortExporter.export(
            [makePort(processName: "weird, \"name\"", frameworkLabel: nil, projectName: nil, gitBranch: nil)],
            format: .csv
        )
        let lines = String(data: data, encoding: .utf8)!.split(separator: "\n")
        #expect(lines[1] == "5173,TCP,4821,\"weird, \"\"name\"\"\",,,")
    }

    @Test func csvLeavesEmptyFieldsForMissingOptionals() {
        let data = PortExporter.export(
            [makePort(frameworkLabel: nil, projectName: nil, gitBranch: nil)],
            format: .csv
        )
        let lines = String(data: data, encoding: .utf8)!.split(separator: "\n")
        #expect(lines[1] == "5173,TCP,4821,node,,,")
    }

    @Test func jsonRoundTripsAllFields() throws {
        let data = PortExporter.export([makePort()], format: .json)
        let rows = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: String]])
        #expect(rows.count == 1)
        #expect(rows[0]["port"] == "5173")
        #expect(rows[0]["proto"] == "TCP")
        #expect(rows[0]["pid"] == "4821")
        #expect(rows[0]["processName"] == "node")
        #expect(rows[0]["frameworkLabel"] == "Vite")
        #expect(rows[0]["projectName"] == "portly-web")
        #expect(rows[0]["gitBranch"] == "main")
    }

    @Test func jsonEmptyListProducesEmptyArray() throws {
        let data = PortExporter.export([], format: .json)
        let rows = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: String]])
        #expect(rows.isEmpty)
    }
}
