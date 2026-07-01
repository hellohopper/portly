import Foundation

enum PortExporter {
    enum Format: String, CaseIterable, Identifiable {
        case json
        case csv

        var id: String { rawValue }
        var fileExtension: String { rawValue }
    }

    static func export(_ ports: [PortInfo], format: Format) -> Data {
        switch format {
        case .json:
            return exportJSON(ports)
        case .csv:
            return exportCSV(ports)
        }
    }

    private static func exportJSON(_ ports: [PortInfo]) -> Data {
        let rows = ports.map { info in
            [
                "port": String(info.port),
                "proto": info.proto,
                "pid": String(info.pid),
                "processName": info.processName,
                "frameworkLabel": info.frameworkLabel ?? "",
                "projectName": info.projectName ?? "",
                "gitBranch": info.gitBranch ?? ""
            ]
        }
        return (try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    private static func exportCSV(_ ports: [PortInfo]) -> Data {
        var lines = ["port,proto,pid,processName,frameworkLabel,projectName,gitBranch"]
        for info in ports {
            let fields = [
                String(info.port),
                info.proto,
                String(info.pid),
                info.processName,
                info.frameworkLabel ?? "",
                info.projectName ?? "",
                info.gitBranch ?? ""
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    private static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
