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

/// SIGTERMs native processes, but routes Docker-forwarded ports through the daemon:
/// their pid is `com.docker.backend`, the forwarder shared by *every* container, so
/// signalling it would take down all Docker port forwarding rather than the one
/// container meant. Mirrors `PortStore.kill` in the app. Returns false when a Docker
/// port couldn't be resolved to a container (and so was deliberately left alone).
@discardableResult
func stopPorts(_ matches: [PortInfo], extraPids: Set<Int32> = []) -> Bool {
    let docker = matches.filter(\.isDockerManaged)
    var pids = Set(matches.filter { !$0.isDockerManaged }.map(\.pid)).union(extraPids)
    // A wrapper tree may include the Docker forwarder too; never signal it.
    let dockerPids = Set(docker.map(\.pid))
    pids.subtract(dockerPids)

    for pid in pids {
        kill(pid, SIGTERM)
    }
    for info in matches where !info.isDockerManaged {
        print("Sent SIGTERM to \(info.processName) (port \(info.port)).")
    }

    guard !docker.isEmpty else { return true }
    let names = runBlocking { await DockerContainerResolver.shared.containerNames(for: docker.map(\.port)) }
    var allStopped = true
    for info in docker {
        guard let container = names[info.port] else {
            FileHandle.standardError.write(Data(
                "Port \(info.port) is forwarded by Docker, but no container could be matched to it -- not killing Docker's shared forwarder.\n".utf8
            ))
            allStopped = false
            continue
        }
        let stopped = runBlocking { await DockerContainerResolver.shared.stop(containerName: container) }
        if stopped {
            print("Stopped container \(container) (port \(info.port)).")
        } else {
            FileHandle.standardError.write(Data("docker stop \(container) failed.\n".utf8))
            allStopped = false
        }
    }
    return allStopped
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

let zshCompletionScript = """
#compdef portly

_portly() {
    local -a commands
    commands=(
        'list:Show listening ports'
        'watch:Re-render the port table every 2s'
        'wait:Block until a port is listening'
        'free:Print an unused port from the common dev ranges'
        'kill:SIGTERM the process listening on a port'
        'restart:Kill and relaunch it with the same command line'
        'run:Run a command with $PORT set to a free port'
        'workspace:Start/stop everything a .portly.json declares'
        'remote:Run portly on another host over ssh'
        'completions:Print a shell completion script'
        'version:Print the version'
        'help:Show help'
    )

    if (( CURRENT == 2 )); then
        _describe 'command' commands
        return
    fi

    case ${words[2]} in
        kill|restart|wait)
            if (( CURRENT == 3 )); then
                local -a ports
                ports=(${(f)"$(portly list --json 2>/dev/null | command grep -o '"port":[0-9]*' | command cut -d: -f2)"})
                _describe 'port' ports
            fi
            ;;
        completions)
            (( CURRENT == 3 )) && _values 'shell' zsh fish
            ;;
        workspace)
            (( CURRENT == 3 )) && _values 'action' up down status
            ;;
        list)
            (( CURRENT == 3 )) && _values 'option' --json
            ;;
    esac
}

_portly
"""

let fishCompletionScript = """
complete -c portly -f
complete -c portly -n '__fish_use_subcommand' -a list -d 'Show listening ports'
complete -c portly -n '__fish_use_subcommand' -a watch -d 'Re-render the port table every 2s'
complete -c portly -n '__fish_use_subcommand' -a wait -d 'Block until a port is listening'
complete -c portly -n '__fish_use_subcommand' -a free -d 'Print an unused port from the common dev ranges'
complete -c portly -n '__fish_use_subcommand' -a kill -d 'SIGTERM the process listening on a port'
complete -c portly -n '__fish_use_subcommand' -a restart -d 'Kill and relaunch it with the same command line'
complete -c portly -n '__fish_use_subcommand' -a run -d 'Run a command with $PORT set to a free port'
complete -c portly -n '__fish_use_subcommand' -a workspace -d 'Start/stop everything a .portly.json declares'
complete -c portly -n '__fish_use_subcommand' -a remote -d 'Run portly on another host over ssh'
complete -c portly -n '__fish_use_subcommand' -a completions -d 'Print a shell completion script'
complete -c portly -n '__fish_use_subcommand' -a version -d 'Print the version'
complete -c portly -n '__fish_use_subcommand' -a help -d 'Show help'
complete -c portly -n '__fish_seen_subcommand_from list' -l json -d 'Machine-readable JSON output'
complete -c portly -n '__fish_seen_subcommand_from completions' -a 'zsh fish'
complete -c portly -n '__fish_seen_subcommand_from workspace' -a 'up down status'
"""

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
        var tick = 0
        while Date() < deadline {
            // A loopback connect answers the common case in a couple of syscalls; the
            // full socket scan (once a second) still catches UDP listeners and servers
            // bound only to a non-loopback interface.
            if LoopbackProbe.isAcceptingConnections(port: port)
                || (tick % 4 == 0 && PortScanner.scan().contains(where: { $0.port == port })) {
                print("Port \(port) is listening.")
                return 0
            }
            tick += 1
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

        var wrappers = Set<Int32>()
        if tree {
            let table = ProcessTable.snapshot().ancestryTable
            for info in matches where !info.isDockerManaged {
                wrappers.formUnion(ProcessTreeResolver.ancestry(of: info.pid, in: table).map(\.pid))
            }
        }
        let ok = stopPorts(matches, extraPids: wrappers)
        if tree && !wrappers.isEmpty {
            print("Also sent SIGTERM to \(wrappers.count) wrapper process\(wrappers.count == 1 ? "" : "es").")
        }
        return ok ? 0 : 1

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
        // Wait for the old process to actually let go of the port; relaunching after a
        // fixed delay raced slow graceful shutdowns into EADDRINUSE.
        if ProcessTerminator.terminateBlocking([target.pid]) == .survived {
            FileHandle.standardError.write(Data("\(target.processName) (pid \(target.pid)) didn't exit; not relaunching.\n".utf8))
            return 1
        }
        guard ProcessLauncher.launch(commandLine: commandLine, workingDirectory: target.workingDirectory) else {
            FileHandle.standardError.write(Data("Killed it, but relaunching failed: \(commandLine)\n".utf8))
            return 1
        }
        print("Restarted \(target.processName) on port \(port).")
        return 0

    case .run(let requestedPort, let command):
        let used = Set(PortScanner.scan().map(\.port))
        let port: Int
        if let requestedPort {
            if used.contains(requestedPort) {
                guard let free = FreePortFinder.suggest(excluding: used) else {
                    FileHandle.standardError.write(Data(
                        "Port \(requestedPort) is in use and no free port was found in the common dev ranges.\n".utf8
                    ))
                    return 1
                }
                FileHandle.standardError.write(Data("Port \(requestedPort) is already in use — using \(free) instead.\n".utf8))
                port = free
            } else {
                port = requestedPort
            }
        } else {
            guard let free = FreePortFinder.suggest(excluding: used) else {
                FileHandle.standardError.write(Data("No free port found in the common dev ranges.\n".utf8))
                return 1
            }
            port = free
        }

        setenv("PORT", String(port), 1)
        FileHandle.standardError.write(Data("PORT=\(port) \(command.joined(separator: " "))\n".utf8))

        // execvp replaces this process outright (PATH search, current environment,
        // stdio all inherited), so the wrapped command owns the terminal exactly as
        // if the user had typed it themselves -- Ctrl+C, exit code, and all.
        var argv: [UnsafeMutablePointer<CChar>?] = command.map { strdup($0) }
        argv.append(nil)
        execvp(command[0], &argv)
        FileHandle.standardError.write(Data("Failed to run \(command[0]): \(String(cString: strerror(errno)))\n".utf8))
        return 127

    case .workspace(let action):
        let cwd = FileManager.default.currentDirectoryPath
        let projectRoot = GitProjectResolver.projectRoot(fromDirectory: cwd)
        let config = ProjectConfigResolver.shared.config(fromDirectory: cwd)

        switch action {
        case .up:
            guard !config.commands.isEmpty else {
                FileHandle.standardError.write(Data("No \"commands\" declared in \(ProjectConfigResolver.fileName) at \(projectRoot.path).\n".utf8))
                return 1
            }
            var failures = 0
            for name in config.commands.keys.sorted() {
                let commandLine = config.commands[name]!
                if ProcessLauncher.launch(commandLine: commandLine, workingDirectory: projectRoot.path) {
                    print("Started \(name): \(commandLine)")
                } else {
                    FileHandle.standardError.write(Data("Failed to start \(name): \(commandLine)\n".utf8))
                    failures += 1
                }
            }
            return failures == 0 ? 0 : 1

        case .down:
            guard !config.expectedPorts.isEmpty else {
                FileHandle.standardError.write(Data("No expected ports declared in \(ProjectConfigResolver.fileName) at \(projectRoot.path).\n".utf8))
                return 1
            }
            let matches = PortScanner.scan().filter { config.expectedPorts.contains($0.port) }
            guard !matches.isEmpty else {
                print("Nothing is listening on this project's expected ports.")
                return 0
            }
            return stopPorts(matches) ? 0 : 1

        case .status:
            guard !config.expectedPorts.isEmpty else {
                FileHandle.standardError.write(Data("No expected ports declared in \(ProjectConfigResolver.fileName) at \(projectRoot.path).\n".utf8))
                return 1
            }
            // Grouped, not uniquely keyed: several processes can share one port
            // (pre-fork servers like `gunicorn -w 4`, SO_REUSEPORT), which used to
            // crash this with "Duplicate values for key".
            let live = Dictionary(grouping: PortScanner.scan(), by: \.port)
            for port in config.expectedPorts.sorted() {
                if let holders = live[port], !holders.isEmpty {
                    let owners = holders
                        .map { "\($0.processName) (pid \($0.pid))" }
                        .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                        .joined(separator: ", ")
                    print("\(port)  up    \(owners)")
                } else {
                    print("\(port)  down")
                }
            }
            return 0
        }

    case .remote(let host, let args):
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [host, "portly"] + args
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        process.standardInput = FileHandle.standardInput
        do {
            try process.run()
        } catch {
            FileHandle.standardError.write(Data("Failed to run ssh: \(error.localizedDescription)\n".utf8))
            return 1
        }
        process.waitUntilExit()
        return process.terminationStatus

    case .completions(let shell):
        print(shell == .zsh ? zshCompletionScript : fishCompletionScript)
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
