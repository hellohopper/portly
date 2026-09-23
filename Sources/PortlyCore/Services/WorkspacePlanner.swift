import Foundation

/// Orders a project's services so each starts only after what it depends on.
public enum WorkspacePlanner {

    public enum PlanError: Error, Equatable, CustomStringConvertible {
        case unknownDependency(service: String, dependency: String)
        case cycle([String])

        public var description: String {
            switch self {
            case .unknownDependency(let service, let dependency):
                return "\"\(service)\" depends on \"\(dependency)\", which isn't declared under \"commands\"."
            case .cycle(let names):
                return "Circular dependency between: \(names.joined(separator: ", "))."
            }
        }
    }

    /// Start order as waves: every service in a wave depends only on earlier waves,
    /// so a wave can start all at once. Names are sorted within a wave, since JSON
    /// object order isn't preserved and something that starts processes should be
    /// deterministic.
    public static func waves(_ services: [String: ProjectConfigResolver.Service]) throws -> [[String]] {
        for (name, service) in services {
            for dependency in service.dependsOn where services[dependency] == nil {
                throw PlanError.unknownDependency(service: name, dependency: dependency)
            }
        }

        var remaining = Set(services.keys)
        var started = Set<String>()
        var waves: [[String]] = []
        while !remaining.isEmpty {
            let ready = remaining
                .filter { name in services[name]!.dependsOn.allSatisfy(started.contains) }
                .sorted()
            guard !ready.isEmpty else { throw PlanError.cycle(remaining.sorted()) }
            waves.append(ready)
            started.formUnion(ready)
            remaining.subtract(ready)
        }
        return waves
    }

    /// Services some other service depends on -- the ones worth waiting for.
    public static func dependedOn(_ services: [String: ProjectConfigResolver.Service]) -> Set<String> {
        Set(services.values.flatMap(\.dependsOn))
    }
}
