import Foundation

/// Parsed CLI invocation, separated from main.swift so it can be unit tested.
enum CLICommand: Equatable {
    case list(json: Bool)
    case watch
    case wait(port: Int, timeout: Int)
    case free
    case kill(port: Int, tree: Bool)
    case restart(port: Int)
    case run(port: Int?, command: [String])
    case completions(ShellKind)
    case version
    case help

    enum ShellKind: String, Equatable {
        case zsh
        case fish
    }

    static let defaultWaitTimeout = 60

    static func parse(_ arguments: [String]) -> CLICommand? {
        guard let first = arguments.first else { return .list(json: false) }

        switch first {
        case "list":
            let rest = Array(arguments.dropFirst())
            if rest.isEmpty { return .list(json: false) }
            if rest == ["--json"] { return .list(json: true) }
            return nil
        case "watch":
            return arguments.count == 1 ? .watch : nil
        case "free":
            return arguments.count == 1 ? .free : nil
        case "wait":
            guard arguments.count >= 2, let port = Int(arguments[1]), (1...65535).contains(port) else { return nil }
            let rest = Array(arguments.dropFirst(2))
            if rest.isEmpty { return .wait(port: port, timeout: defaultWaitTimeout) }
            guard rest.count == 2, rest[0] == "--timeout",
                  let timeout = Int(rest[1]), timeout > 0 else { return nil }
            return .wait(port: port, timeout: timeout)
        case "kill":
            guard arguments.count >= 2, let port = Int(arguments[1]), (1...65535).contains(port) else { return nil }
            let rest = Array(arguments.dropFirst(2))
            if rest.isEmpty { return .kill(port: port, tree: false) }
            guard rest == ["--tree"] else { return nil }
            return .kill(port: port, tree: true)
        case "restart":
            guard arguments.count == 2, let port = Int(arguments[1]), (1...65535).contains(port) else { return nil }
            return .restart(port: port)
        case "run":
            let rest = Array(arguments.dropFirst())
            var port: Int?
            var index = 0
            if rest.first == "--port" {
                guard rest.count >= 2, let requested = Int(rest[1]), (1...65535).contains(requested) else { return nil }
                port = requested
                index = 2
            }
            guard index < rest.count, rest[index] == "--" else { return nil }
            let command = Array(rest[(index + 1)...])
            guard !command.isEmpty else { return nil }
            return .run(port: port, command: command)
        case "completions":
            guard arguments.count == 2, let shell = ShellKind(rawValue: arguments[1]) else { return nil }
            return .completions(shell)
        case "version", "--version", "-v":
            return .version
        case "help", "--help", "-h":
            return .help
        default:
            return nil
        }
    }

    static let usage = """
    portly — track and manage local listening ports

    USAGE: portly [command]

    COMMANDS:
      list             Show listening ports (default)
      list --json      Machine-readable JSON output
      watch            Re-render the port table every 2s until interrupted (Ctrl+C)
      wait <port>      Block until something is listening on <port>
                       (--timeout <seconds>, default 60; exits 1 on timeout)
      free             Print an unused port from the common dev ranges
      kill <port>      SIGTERM the process listening on <port>
                       (--tree also kills its wrapper processes, e.g. npm -> node)
      restart <port>   Kill and relaunch it with the same command line
      run -- <cmd>     Run <cmd> with $PORT set to a free port (avoids "already in
                       use" errors); --port <n> requests a specific one, falling
                       back to another free port if <n> is taken
      completions <shell>
                       Print a completion script for zsh or fish
      version          Print the version
      help             Show this help

    EXIT CODES:
      0  success
      1  the requested port had no listener / wait timed out
      64 usage error
    """
}
