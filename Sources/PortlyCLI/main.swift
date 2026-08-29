import Foundation
import PortlyCore
#if canImport(Darwin)
import Darwin
#endif

/// Bundle.main resolves the app bundle from argv[0] as invoked, not the real
/// executable location -- so running via the Homebrew-installed `portly` symlink
/// (/opt/homebrew/bin/portly -> Portly.app/Contents/MacOS/portly-cli) fails to find
/// Info.plist and silently falls back to nil. _NSGetExecutablePath + realpath gives
/// the actual on-disk location regardless of how the symlink was invoked.
func appBundleVersion() -> String? {
    var size: UInt32 = 0
    _NSGetExecutablePath(nil, &size)
    var pathBuffer = [Int8](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&pathBuffer, &size) == 0 else { return nil }

    var realBuffer = [Int8](repeating: 0, count: Int(PATH_MAX))
    guard realpath(pathBuffer, &realBuffer) != nil else { return nil }
    let executableURL = URL(fileURLWithPath: String(cString: realBuffer))

    // executableURL: .../Portly.app/Contents/MacOS/portly-cli
    let bundleURL = executableURL
        .deletingLastPathComponent() // MacOS
        .deletingLastPathComponent() // Contents
        .deletingLastPathComponent() // Portly.app
    return Bundle(url: bundleURL)?.infoDictionary?["CFBundleShortVersionString"] as? String
}

/// Shares the app's enrichment pipeline, minus throughput -- that needs a long-lived
/// `nettop`, which a one-shot command has no way to sample.
func enrichedPorts() -> [PortInfo] {
    let scanned = PortScanner.scan().sorted { $0.port < $1.port }
    return runBlocking { await PortEnricher.enrich(scanned, options: .oneShot).ports }
}

/// Bridges the async pipeline into this synchronous top-level CLI.
func runBlocking<T: Sendable>(_ work: @escaping @Sendable () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task {
        box.value = await work()
        semaphore.signal()
    }
    semaphore.wait()
    return box.value!
}

final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}

let watchTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()

func printTable(_ ports: [PortInfo]) {
    guard !ports.isEmpty else {
        print("No listening ports.")
        return
    }

    var rows: [[String]] = [["PORT", "BIND", "PROTO", "PID", "PROCESS", "FRAMEWORK", "PROJECT", "UPTIME"]]
    for info in ports {
        rows.append([
            String(info.port),
            info.isExposedToNetwork ? "LAN" : "local",
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

    case .watch:
        while true {
            print("\u{1B}[2J\u{1B}[H", terminator: "") // clear screen, cursor to top-left
            print("portly watch — updated \(watchTimeFormatter.string(from: Date())) (Ctrl+C to quit)\n")
            printTable(enrichedPorts())
            fflush(stdout)
            Thread.sleep(forTimeInterval: 2)
        }

    case .wait(let port, let timeout):
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while Date() < deadline {
            if PortScanner.scan().contains(where: { $0.port == port }) {
                print("Port \(port) is listening.")
                return 0
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        FileHandle.standardError.write(Data("Timed out after \(timeout)s waiting for port \(port).\n".utf8))
        return 1

    case .free:
        let used = Set(PortScanner.scan().map(\.port))
        guard let port = FreePortFinder.suggest(excluding: used) else {
            FileHandle.standardError.write(Data("No free port found in the common dev ranges.\n".utf8))
            return 1
        }
        print(port)
        return 0

    case .kill(let port, let tree):
        let matches = PortScanner.scan().filter { $0.port == port }
        guard !matches.isEmpty else {
            FileHandle.standardError.write(Data("No process is listening on port \(port).\n".utf8))
            return 1
        }

        var pids = Set(matches.map(\.pid))
        if tree {
            // Outermost first, so nothing respawns the leaf.
            let table = ProcessTable.snapshot().ancestryTable
            for info in matches {
                pids.formUnion(ProcessTreeResolver.ancestry(of: info.pid, in: table).map(\.pid))
            }
        }
        for pid in pids {
            kill(pid, SIGTERM)
        }
        let names = Set(matches.map(\.processName)).sorted().joined(separator: ", ")
        print("Sent SIGTERM to \(names) (port \(port))\(tree ? " and its wrappers" : "").")
        return 0

    case .restart(let port):
        let matches = enrichedPorts().filter { $0.port == port }
        guard let target = matches.first else {
            FileHandle.standardError.write(Data("No process is listening on port \(port).\n".utf8))
            return 1
        }
        guard let commandLine = target.commandLine else {
            FileHandle.standardError.write(Data("Couldn't read the command line for port \(port).\n".utf8))
            return 1
        }
        kill(target.pid, SIGTERM)
        Thread.sleep(forTimeInterval: 0.5)
        guard ProcessLauncher.launch(commandLine: commandLine, workingDirectory: target.workingDirectory) else {
            FileHandle.standardError.write(Data("Killed it, but relaunching failed: \(commandLine)\n".utf8))
            return 1
        }
        print("Restarted \(target.processName) on port \(port).")
        return 0

    case .version:
        // A bare `swift build` binary (not inside Portly.app) has no bundle version.
        print(appBundleVersion() ?? "dev")
        return 0

    case .help:
        print(CLICommand.usage)
        return 0
    }
}

exit(run())
