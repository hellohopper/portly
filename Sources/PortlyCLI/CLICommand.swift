import Foundation

/// Parsed CLI invocation, separated from main.swift so it can be unit tested.
enum CLICommand: Equatable {
    case list(json: Bool)
    case watch
    case wait(port: Int, timeout: Int)
    case free
    case kill(port: Int, tree: Bool)
    case restart(port: Int)
    case version
    case help

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
      version          Print the version
      help             Show this help

    EXIT CODES:
      0  success
      1  the requested port had no listener / wait timed out
      64 usage error
    """
}
