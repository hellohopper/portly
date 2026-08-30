import Foundation

/// A rolling, in-memory log of requests the `.localhost` proxy has forwarded, so
/// "is anything even hitting this?" doesn't require reaching for `curl` or the
/// browser's network tab. The proxy is a dumb byte-pipe by design (websockets/SSE
/// included), so this only ever sees the request line -- no response status, no body.
public actor ProxyRequestLog {
    public static let shared = ProxyRequestLog()

    public struct Entry: Sendable, Identifiable, Equatable {
        public let id = UUID()
        public let date: Date
        public let name: String
        public let targetPort: Int
        public let method: String
        public let path: String
    }

    /// Per-name cap, not global: a chatty project's proxy traffic shouldn't crowd out
    /// a quiet one's handful of requests.
    private static let maxEntriesPerName = 30

    private var entriesByName: [String: [Entry]] = [:]

    private init() {}

    public func record(name: String, targetPort: Int, requestLine: String, at date: Date = Date()) {
        guard let (method, path) = Self.parse(requestLine: requestLine) else { return }
        let entry = Entry(date: date, name: name, targetPort: targetPort, method: method, path: path)

        var entries = entriesByName[name] ?? []
        entries.insert(entry, at: 0) // newest first
        if entries.count > Self.maxEntriesPerName {
            entries.removeLast(entries.count - Self.maxEntriesPerName)
        }
        entriesByName[name] = entries
    }

    /// Newest first.
    public func recent(for name: String) -> [Entry] {
        entriesByName[name] ?? []
    }

    public func clear(name: String) {
        entriesByName[name] = nil
    }

    /// Parses "GET /path HTTP/1.1" -> ("GET", "/path"). Anything else (a malformed or
    /// non-HTTP first line, e.g. a raw TCP client that isn't speaking HTTP at all)
    /// yields no entry rather than a fabricated one.
    static func parse(requestLine: String) -> (method: String, path: String)? {
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0].allSatisfy({ $0.isUppercase }) else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
}
