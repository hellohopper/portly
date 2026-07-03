import Foundation
import PortlyCore

func enrichedPorts() -> [PortInfo] {
    let scanned = PortScanner.scan().sorted { $0.port < $1.port }
    let uniquePids = Array(Set(scanned.map(\.pid)))
    let uptimes = UptimeResolver.elapsedSeconds(for: uniquePids)
    let commandLines = CommandLineResolver.commandLines(for: uniquePids)

    return scanned.map { info in
        var info = info
        info.uptimeSeconds = uptimes[info.pid]
        if let commandLine = commandLines[info.pid] {
            info.commandLine = commandLine
            info.frameworkLabel = FrameworkDetector.detect(
                processName: info.processName, commandLine: commandLine
            )
        }
        let context = GitProjectResolver.resolve(pid: info.pid)
        info.projectName = context.projectName
        info.gitBranch = context.gitBranch
        return info
    }
}

func printTable(_ ports: [PortInfo]) {
    guard !ports.isEmpty else {
        print("No listening ports.")
        return
    }

    var rows: [[String]] = [["PORT", "PROTO", "PID", "PROCESS", "FRAMEWORK", "PROJECT", "UPTIME"]]
    for info in ports {
        rows.append([
            String(info.port),
            info.proto,
            String(info.pid),
            info.processName,
            info.frameworkLabel ?? "-",
            info.projectName.map { name in
                info.gitBranch.map { "\(name) (\($0))" } ?? name
            } ?? "-",
            info.uptimeSeconds.map(UptimeResolver.format) ?? "-"
        ])
    }

    let widths = (0..<rows[0].count).map { column in
        rows.map { $0[column].count }.max() ?? 0
    }
    for row in rows {
        let line = row.enumerated()
            .map { $0.element.padding(toLength: widths[$0.offset], withPad: " ", startingAt: 0) }
            .joined(separator: "  ")
        print(line)
    }
}

func run() -> Int32 {
    guard let command = CLICommand.parse(Array(CommandLine.arguments.dropFirst())) else {
        FileHandle.standardError.write(Data("Unrecognized arguments.\n\n\(CLICommand.usage)\n".utf8))
        return 64 // EX_USAGE
    }

    switch command {
    case .list(let json):
        let ports = enrichedPorts()
        if json {
            FileHandle.standardOutput.write(PortExporter.export(ports, format: .json))
            print("")
        } else {
            printTable(ports)
        }
        return 0

    case .kill(let port):
        let matches = PortScanner.scan().filter { $0.port == port }
        guard !matches.isEmpty else {
            FileHandle.standardError.write(Data("No process is listening on port \(port).\n".utf8))
            return 1
        }
        for info in Set(matches.map(\.pid)) {
            kill(info, SIGTERM)
        }
        let names = Set(matches.map(\.processName)).sorted().joined(separator: ", ")
        print("Sent SIGTERM to \(names) (port \(port)).")
        return 0

    case .version:
        // Inside Portly.app, Bundle.main resolves to the app bundle and reports its
        // version; a bare `swift build` binary has no bundle version.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        print(version ?? "dev")
        return 0

    case .help:
        print(CLICommand.usage)
        return 0
    }
}

exit(run())
