import Foundation

public enum PortExporter {
    public enum Format: String, CaseIterable, Identifiable, Sendable {
        case json
        case csv

        public var id: String { rawValue }
        public var fileExtension: String { rawValue }
    }

    public static func export(_ ports: [PortInfo], format: Format) -> Data {
        switch format {
        case .json:
            return exportJSON(ports)
        case .csv:
            return exportCSV(ports)
        }
    }

    /// The single definition of an exported row, so JSON and CSV can't drift apart
    /// as fields are added.
    static func fields(for info: PortInfo) -> [(name: String, value: String)] {
        [
            ("port", String(info.port)),
            ("proto", info.proto),
            ("pid", String(info.pid)),
            ("processName", info.processName),
            ("frameworkLabel", info.frameworkLabel ?? ""),
            ("projectName", info.projectName ?? ""),
            ("gitBranch", info.gitBranch ?? ""),
            ("bindAddress", info.bindAddress ?? ""),
            ("exposedToNetwork", info.isExposedToNetwork ? "true" : "false")
        ]
    }

    private static func exportJSON(_ ports: [PortInfo]) -> Data {
        let rows = ports.map { info in
            Dictionary(uniqueKeysWithValues: fields(for: info).map { ($0.name, $0.value) })
        }
        return (try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    private static func exportCSV(_ ports: [PortInfo]) -> Data {
        // The field list is fixed, so an empty export still gets the right header.
        let template = PortInfo(pid: 0, port: 0, proto: "", processName: "", commandPath: nil)
        let header = fields(for: ports.first ?? template).map(\.name)

        var lines = [header.joined(separator: ",")]
        for info in ports {
            lines.append(fields(for: info).map(\.value).map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    private static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
