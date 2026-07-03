import Foundation

/// Probes local TCP ports with an HTTP HEAD request so the UI can show whether a
/// dev server is actually responding (and with what status), not just listening.
public actor HealthChecker {
    public static let shared = HealthChecker()

    public enum Category: Sendable {
        case healthy   // 2xx / 3xx
        case warning   // 4xx -- responding, but erroring on "/"
        case failing   // 5xx

        public static func classify(statusCode: Int) -> Category {
            switch statusCode {
            case ..<400: return .healthy
            case 400..<500: return .warning
            default: return .failing
            }
        }
    }

    /// Ports are re-probed at most this often; between probes the cached status is
    /// returned so the 2s port-list refresh doesn't hammer local servers.
    private let recheckInterval: TimeInterval = 10

    private struct CacheEntry {
        let status: Int?
        let checkedAt: Date
    }

    private var cache: [Int: CacheEntry] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.0
        config.timeoutIntervalForResource = 2.0
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    /// Returns the latest known HTTP status per port, probing any port whose cached
    /// result is stale. Non-HTTP ports (connection refused, handshake garbage,
    /// timeout) yield no entry.
    public func statuses(for ports: [Int]) async -> [Int: Int] {
        let now = Date()
        let stalePorts = ports.filter { port in
            guard let entry = cache[port] else { return true }
            return now.timeIntervalSince(entry.checkedAt) >= recheckInterval
        }

        await withTaskGroup(of: (Int, Int?).self) { group in
            for port in stalePorts {
                group.addTask { (port, await self.probe(port: port)) }
            }
            for await (port, status) in group {
                cache[port] = CacheEntry(status: status, checkedAt: now)
            }
        }

        // Drop cache entries for ports that no longer exist.
        let live = Set(ports)
        cache = cache.filter { live.contains($0.key) }

        return cache.compactMapValues(\.status)
    }

    private func probe(port: Int) async -> Int? {
        guard let url = URL(string: "http://localhost:\(port)/") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        guard let (_, response) = try? await session.data(for: request) else { return nil }
        return (response as? HTTPURLResponse)?.statusCode
    }
}
