import Foundation

/// `portly://` deep links, so launchers (Raycast, Alfred, Shortcuts) and scripts
/// can drive the app: `open portly://kill/3000`.
public enum PortlyURLCommand: Equatable, Sendable {
    /// Show the menu bar panel, optionally pre-filled with a search.
    case show(search: String?)
    case open(port: Int)
    case copy(port: Int)
    case pin(port: Int)
    case unpin(port: Int)
    case kill(port: Int)
    case forceKill(port: Int)
    case restart(port: Int)

    public static let scheme = "portly"

    /// Whether this action stops or restarts a process. Links can be opened by any
    /// web page the user visits, so these need a confirmation unless the user has
    /// explicitly trusted the scheme.
    public var isDestructive: Bool {
        switch self {
        case .kill, .forceKill, .restart: return true
        case .show, .open, .copy, .pin, .unpin: return false
        }
    }

    public var port: Int? {
        switch self {
        case .show: return nil
        case .open(let port), .copy(let port), .pin(let port), .unpin(let port),
             .kill(let port), .forceKill(let port), .restart(let port):
            return port
        }
    }

    /// Accepts `portly://<action>/<port>` and `portly://<action>?port=<port>`.
    public static func parse(_ url: URL) -> PortlyURLCommand? {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let action = (components.host ?? "").lowercased()
        let queryItems = components.queryItems ?? []

        if action == "show" || action.isEmpty {
            let search = queryItems.first { $0.name == "search" }?.value
            return .show(search: search?.isEmpty == true ? nil : search)
        }

        let pathPort = components.path.split(separator: "/").first.flatMap { Int($0) }
        let queryPort = queryItems.first { $0.name == "port" }?.value.flatMap(Int.init)
        guard let port = pathPort ?? queryPort, (1...65535).contains(port) else { return nil }

        switch action {
        case "open": return .open(port: port)
        case "copy": return .copy(port: port)
        case "pin": return .pin(port: port)
        case "unpin": return .unpin(port: port)
        case "kill": return .kill(port: port)
        case "force-kill", "forcekill": return .forceKill(port: port)
        case "restart": return .restart(port: port)
        default: return nil
        }
    }
}
