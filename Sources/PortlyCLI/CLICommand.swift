import Foundation

/// Parsed CLI invocation, separated from main.swift so it can be unit tested.
enum CLICommand: Equatable {
    case list(json: Bool)
    case kill(port: Int)
    case version
    case help

    static func parse(_ arguments: [String]) -> CLICommand? {
        guard let first = arguments.first else { return .list(json: false) }

        switch first {
        case "list":
            let rest = Array(arguments.dropFirst())
            if rest.isEmpty { return .list(json: false) }
            if rest == ["--json"] { return .list(json: true) }
            return nil
        case "kill":
            guard arguments.count == 2, let port = Int(arguments[1]), (1...65535).contains(port) else { return nil }
            return .kill(port: port)
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
      kill <port>      SIGTERM the process listening on <port>
      version          Print the version
      help             Show this help
    """
}
