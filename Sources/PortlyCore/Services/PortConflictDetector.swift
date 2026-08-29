import Foundation

/// A port a project declared in `.portly.json` that something else is sitting on.
public struct PortConflict: Identifiable, Sendable, Equatable {
    /// The port the project expected to use.
    public let port: Int
    /// The project that declared it (its root's directory name).
    public let expectedBy: String
    /// The label that project gave the port, when it gave one.
    public let expectedLabel: String?
    /// The process currently holding it.
    public let heldBy: PortInfo

    public var id: Int { port }

    public init(port: Int, expectedBy: String, expectedLabel: String?, heldBy: PortInfo) {
        self.port = port
        self.expectedBy = expectedBy
        self.expectedLabel = expectedLabel
        self.heldBy = heldBy
    }
}

/// Answers the standard morning failure: yesterday's server still holds 3000, so
/// today's `npm run dev` quietly binds 3001 and you spend ten minutes debugging
/// callback URLs against the wrong origin.
public enum PortConflictDetector {

    /// A declared port conflicts when something is listening on it and that something
    /// belongs to a *different* project than the one that declared it. A declared port
    /// nothing is using isn't a conflict -- that server simply isn't running yet.
    public static func conflicts(
        configsByProjectRoot: [String: ProjectConfigResolver.Config],
        projectRootByPort: [Int: String],
        ports: [PortInfo]
    ) -> [PortConflict] {
        var holderByPort: [Int: PortInfo] = [:]
        for info in ports where holderByPort[info.port] == nil {
            holderByPort[info.port] = info
        }

        var conflicts: [PortConflict] = []
        for (root, config) in configsByProjectRoot {
            for port in config.expectedPorts {
                guard let holder = holderByPort[port] else { continue }
                // Held by the project that declared it: business as usual.
                guard projectRootByPort[port] != root else { continue }
                conflicts.append(
                    PortConflict(
                        port: port,
                        expectedBy: URL(fileURLWithPath: root).lastPathComponent,
                        expectedLabel: config.labels[port],
                        heldBy: holder
                    )
                )
            }
        }
        return conflicts.sorted { $0.port < $1.port }
    }
}
