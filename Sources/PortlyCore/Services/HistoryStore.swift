import Foundation

/// Rolling log of port open/close events, persisted as JSON so it survives
/// relaunches. Answers "what was running on 3000 an hour ago?"
@MainActor
public final class HistoryStore: ObservableObject {
    public struct Event: Codable, Identifiable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case opened
            case closed
            /// The port stayed up but changed owner -- a restart that completed
            /// between two polls.
            case replaced
        }

        public var id = UUID()
        public let date: Date
        public let kind: Kind
        public let port: Int
        public let processName: String
        public let projectName: String?
        /// Captured so a closed port can be started again -- restart only works while
        /// the process is alive, and the moment it's killed the command line is gone.
        /// Optional for backward compatibility with history written before this existed.
        public var commandLine: String?
        public var workingDirectory: String?

        /// Whether this event carries enough detail to relaunch it.
        public var isRelaunchable: Bool {
            kind == .closed && commandLine?.isEmpty == false && workingDirectory != nil
        }
    }

    public static let maxEvents = 300

    @Published public private(set) var events: [Event] = []

    private let fileURL: URL

    /// Default persistence location: ~/Library/Application Support/Portly/history.json.
    /// Tests inject a temp URL instead.
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Portly/history.json")
        events = Self.load(from: self.fileURL)
    }

    public func record(
        opened: [PortInfo],
        closed: [PortInfo],
        replaced: [PortInfo] = [],
        at date: Date = Date()
    ) {
        guard !opened.isEmpty || !closed.isEmpty || !replaced.isEmpty else { return }

        var newEvents: [Event] = []
        for info in opened {
            newEvents.append(Event(date: date, kind: .opened, port: info.port,
                                   processName: info.processName, projectName: info.projectName))
        }
        for info in closed {
            newEvents.append(Event(date: date, kind: .closed, port: info.port,
                                   processName: info.processName, projectName: info.projectName,
                                   commandLine: info.commandLine, workingDirectory: info.workingDirectory))
        }
        for info in replaced {
            newEvents.append(Event(date: date, kind: .replaced, port: info.port,
                                   processName: info.processName, projectName: info.projectName))
        }

        events = Array((newEvents + events).prefix(Self.maxEvents))
        save()
    }

    public func clear() {
        events = []
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(events).write(to: fileURL)
        } catch {
            // History is best-effort; a failed save just means it won't survive relaunch.
        }
    }

    private static func load(from fileURL: URL) -> [Event] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Event].self, from: data)) ?? []
    }
}
