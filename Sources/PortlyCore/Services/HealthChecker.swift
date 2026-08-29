import Foundation

/// Probes local ports over HTTP so the UI can show whether a dev server is actually
/// responding -- and how fast -- not just whether the socket is open.
public actor HealthChecker {
    public static let shared = HealthChecker()

    public enum Category: Sendable {
        case healthy   // 2xx / 3xx, answering promptly
        case slow      // responding, but slowly enough to be the actual problem
        case warning   // 4xx -- responding, but erroring on the probed path
        case failing   // 5xx

        public static func classify(statusCode: Int) -> Category {
            switch statusCode {
            case ..<400: return .healthy
            case 400..<500: return .warning
            default: return .failing
            }
        }

        /// A dev server's common real failure is a wedged 30-second response, not a
        /// dead socket, so latency upgrades an otherwise-healthy result to `.slow`.
        public static func classify(statusCode: Int, latency: TimeInterval?) -> Category {
            let base = classify(statusCode: statusCode)
            guard base == .healthy, let latency, latency >= slowThreshold else { return base }
            return .slow
        }

        public static let slowThreshold: TimeInterval = 1.0
    }

    public struct Health: Sendable, Equatable {
        public let statusCode: Int
        public let latency: TimeInterval

        public init(statusCode: Int, latency: TimeInterval) {
            self.statusCode = statusCode
            self.latency = latency
        }

        public var category: Category {
            Category.classify(statusCode: statusCode, latency: latency)
        }
    }

    /// What to probe for a given port. Defaults to `/` over plain HTTP; a project's
    /// `.portly.json` (or a per-port override) can point at a real health endpoint,
    /// because an API-only service 404s on `/` forever and the badge becomes noise.
    public struct Target: Sendable, Equatable {
        public var path: String
        public var useTLS: Bool

        public init(path: String = "/", useTLS: Bool = false) {
            self.path = path.hasPrefix("/") ? path : "/" + path
            self.useTLS = useTLS
        }

        public static let `default` = Target()
    }

    /// Ports are re-probed at most this often; between probes the cached result is
    /// returned so the port-list refresh doesn't hammer local servers.
    private let recheckInterval: TimeInterval
    private let now: @Sendable () -> Date

    private struct CacheEntry {
        let health: Health?
        let checkedAt: Date
        let target: Target
    }

    private var cache: [Int: CacheEntry] = [:]

    /// `now` is injectable so cache expiry can be tested without sleeping.
    public init(recheckInterval: TimeInterval = 10, now: @escaping @Sendable () -> Date = { Date() }) {
        self.recheckInterval = recheckInterval
        self.now = now
    }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.0
        config.timeoutIntervalForResource = 5.0
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(
            configuration: config,
            delegate: LoopbackTLSDelegate(),
            delegateQueue: nil
        )
    }()

    /// Latest known health per port, re-probing any port whose cached result is stale
    /// or whose target changed. Non-HTTP ports (connection refused, handshake
    /// garbage, timeout) yield no entry.
    public func health(for ports: [Int], targets: [Int: Target] = [:]) async -> [Int: Health] {
        let timestamp = now()
        let stalePorts = ports.filter { port in
            guard let entry = cache[port] else { return true }
            if entry.target != (targets[port] ?? .default) { return true }
            return timestamp.timeIntervalSince(entry.checkedAt) >= recheckInterval
        }

        await withTaskGroup(of: (Int, Health?).self) { group in
            for port in stalePorts {
                let target = targets[port] ?? .default
                group.addTask { (port, await self.probe(port: port, target: target)) }
            }
            for await (port, health) in group {
                cache[port] = CacheEntry(
                    health: health, checkedAt: timestamp, target: targets[port] ?? .default
                )
            }
        }

        // Drop cache entries for ports that no longer exist.
        let live = Set(ports)
        cache = cache.filter { live.contains($0.key) }

        return cache.compactMapValues(\.health)
    }

    /// Back-compatible status-code-only view.
    public func statuses(for ports: [Int], targets: [Int: Target] = [:]) async -> [Int: Int] {
        await health(for: ports, targets: targets).mapValues(\.statusCode)
    }

    private func probe(port: Int, target: Target) async -> Health? {
        let scheme = target.useTLS ? "https" : "http"
        guard let url = URL(string: "\(scheme)://localhost:\(port)\(target.path)") else { return nil }

        let started = Date()
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        if let (_, response) = try? await session.data(for: request),
           let http = response as? HTTPURLResponse {
            return Health(statusCode: http.statusCode, latency: Date().timeIntervalSince(started))
        }

        // Some endpoints reject HEAD outright; retry once with a ranged GET before
        // concluding the port isn't speaking HTTP.
        var getRequest = URLRequest(url: url)
        getRequest.httpMethod = "GET"
        getRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        guard let (_, response) = try? await session.data(for: getRequest),
              let http = response as? HTTPURLResponse else { return nil }
        return Health(statusCode: http.statusCode, latency: Date().timeIntervalSince(started))
    }
}

/// Local dev servers use self-signed certificates almost by definition, so an HTTPS
/// probe has to skip validation -- but *only* for loopback. Anything else keeps the
/// system's normal trust evaluation.
private final class LoopbackTLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              Self.loopbackHosts.contains(challenge.protectionSpace.host.lowercased()),
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
