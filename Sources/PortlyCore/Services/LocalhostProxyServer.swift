import Foundation
import Network

/// A loopback-only TCP reverse proxy that routes `http://<name>.localhost:<port>`
/// requests to whichever local port `<name>` is mapped to. Sniffs the `Host` header
/// out of the raw byte stream rather than parsing full HTTP or terminating TLS, then
/// pipes the connection through unmodified -- keeps this a dumb, protocol-agnostic
/// forwarder that works for websockets/SSE too, not just plain request/response HTTP.
public final class LocalhostProxyServer: @unchecked Sendable {
    public static let shared = LocalhostProxyServer()

    /// Fixed rather than user-configurable: every mapped name shares this one port, so
    /// there's only ever a single number to remember (`name.localhost:7777`), not one
    /// per project. Going lower (e.g. 80) would need root and is out of scope.
    public static let port: UInt16 = 7777

    /// Reported back on the main queue after `start()` so the UI can surface a
    /// message instead of the proxy silently never accepting connections.
    public enum State: Sendable, Equatable {
        case stopped
        case listening
        case failed(String)
    }

    private let routesLock = NSLock()
    private var routes: [String: Int] = [:]
    /// Guards `listener`/`generation`, which are touched from both the main thread
    /// (start/stop) and the listener's own queue (state updates).
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var generation = 0

    /// Set by the caller before `start()`; invoked on the main queue.
    public var onStateChange: (@Sendable (State) -> Void)?

    private init() {}

    /// Starts the listener if it isn't already running. Safe to call repeatedly.
    public func start() {
        stateLock.lock()
        guard listener == nil else { stateLock.unlock(); return }
        generation &+= 1
        let generation = self.generation
        stateLock.unlock()

        let parameters = NWParameters.tcp
        // Bind loopback-only: this must never be reachable from the network, only
        // from the machine it's running on.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!
        )
        parameters.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: parameters) else {
            report(.failed("Couldn't create the localhost proxy listener."))
            return
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            // A stale listener (already replaced by a stop()/start() cycle) must not
            // clear the *current* listener's reference -- doing so deallocates the
            // live one, silently killing the proxy while the UI still reads healthy.
            guard self.isCurrent(generation) else { return }

            switch state {
            case .ready:
                self.report(.listening)
            case .waiting(let error), .failed(let error):
                // .waiting means Network.framework intends to keep retrying (e.g. the
                // port is already in use) -- for a fixed, single-purpose port that
                // will never resolve on its own, so treat it the same as a hard
                // failure and stop retrying rather than spinning silently forever.
                self.report(.failed(Self.describe(error)))
                listener?.cancel()
            case .cancelled:
                self.clearListener(generation)
                self.report(.stopped)
            default:
                break
            }
        }
        listener.start(queue: .global(qos: .utility))

        stateLock.lock()
        // A stop() may have landed between the guard above and here.
        if self.generation == generation {
            self.listener = listener
        } else {
            listener.cancel()
        }
        stateLock.unlock()
    }

    public func stop() {
        stateLock.lock()
        let current = listener
        listener = nil
        generation &+= 1
        stateLock.unlock()
        current?.cancel()
    }

    private func isCurrent(_ generation: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return self.generation == generation
    }

    private func clearListener(_ generation: Int) {
        stateLock.lock()
        if self.generation == generation { listener = nil }
        stateLock.unlock()
    }

    private func report(_ state: State) {
        let handler = onStateChange
        DispatchQueue.main.async { handler?(state) }
    }

    private static func describe(_ error: NWError) -> String {
        if case .posix(let code) = error, code == .EADDRINUSE {
            return "Port \(Self.port) is already in use by another app."
        }
        return "Localhost proxy failed to start: \(error.debugDescription)"
    }

    /// Replaces the full name -> port routing table. Called whenever the user edits a
    /// name or the underlying port list changes, so stale mappings stop resolving.
    public func updateRoutes(_ routes: [String: Int]) {
        routesLock.lock()
        self.routes = routes
        routesLock.unlock()
    }

    private func resolvePort(for name: String) -> Int? {
        routesLock.lock()
        defer { routesLock.unlock() }
        return routes[name]
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        readHeader(from: connection, buffer: Data())
    }

    private func readHeader(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }

            var combined = buffer
            if let data { combined.append(data) }

            if let headerEnd = combined.range(of: Data("\r\n\r\n".utf8)) {
                self.route(connection: connection, headerBytes: combined, headerEnd: headerEnd.upperBound)
                return
            }

            // No blank line yet -- keep buffering, up to a sane cap so a client that
            // never sends one can't hold a connection (and this queue) open forever.
            guard error == nil, !isComplete, combined.count < 16_384 else {
                connection.cancel()
                return
            }

            self.readHeader(from: connection, buffer: combined)
        }
    }

    private func route(connection: NWConnection, headerBytes: Data, headerEnd: Int) {
        guard let headerText = String(data: headerBytes.prefix(headerEnd), encoding: .utf8),
              let host = Self.hostHeader(from: headerText),
              let name = Self.proxyName(fromHost: host) else {
            connection.cancel()
            return
        }

        guard let targetPort = resolvePort(for: name), let nwPort = NWEndpoint.Port(rawValue: UInt16(targetPort)) else {
            respondNotFound(on: connection, name: name)
            return
        }

        let upstream = NWConnection(host: "127.0.0.1", port: nwPort, using: .tcp)
        upstream.start(queue: .global(qos: .utility))
        // Replay everything read so far (headers, and any body bytes swept up in the
        // same read) before continuing to pipe the rest of the connection through.
        upstream.send(content: headerBytes, completion: .contentProcessed { _ in })

        // Both directions must finish before the pair is torn down; whichever ends
        // first only half-closes.
        let pair = ConnectionPair(client: connection, upstream: upstream)
        pipe(from: connection, to: upstream, pair: pair)
        pipe(from: upstream, to: connection, pair: pair)
    }

    /// Tracks how many of a proxied connection's two directions have finished, so the
    /// sockets are released once -- and only once -- both are done.
    private final class ConnectionPair: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = 0
        let client: NWConnection
        let upstream: NWConnection

        init(client: NWConnection, upstream: NWConnection) {
            self.client = client
            self.upstream = upstream
        }

        /// Returns true when this was the second (final) direction to finish.
        func directionFinished() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            finished += 1
            return finished >= 2
        }

        func cancelBoth() {
            client.cancel()
            upstream.cancel()
        }
    }

    private func pipe(from source: NWConnection, to destination: NWConnection, pair: ConnectionPair) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { _ in })
            }
            if error != nil {
                pair.cancelBoth()
                return
            }
            if isComplete {
                // A half-close on this direction only means this side finished sending
                // (the standard "write request, shutdown(SHUT_WR), read response"
                // pattern). Forward the FIN and let the other direction keep running --
                // cancelling both here would discard the response the client is waiting
                // for.
                destination.send(content: nil, isComplete: true, completion: .contentProcessed { _ in })
                if pair.directionFinished() { pair.cancelBoth() }
                return
            }
            self?.pipe(from: source, to: destination, pair: pair)
        }
    }

    private func respondNotFound(on connection: NWConnection, name: String) {
        let body = "Portly: no port is mapped to \(name).localhost."
        let response = "HTTP/1.1 404 Not Found\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n"
            + body
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    static func hostHeader(from headerText: String) -> String? {
        for line in headerText.components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            guard line[line.startIndex..<colon].lowercased() == "host" else { continue }
            return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Extracts `myapp` from a `Host` header value like `myapp.localhost` or
    /// `myapp.localhost:7777`. Returns nil for anything not under `.localhost`.
    static func proxyName(fromHost host: String) -> String? {
        let hostname = host.split(separator: ":", maxSplits: 1).first.map(String.init) ?? host
        let suffix = ".localhost"
        guard hostname.lowercased().hasSuffix(suffix), hostname.count > suffix.count else { return nil }
        return String(hostname.dropLast(suffix.count)).lowercased()
    }

    /// Validates a user-entered `.localhost` label: DNS-label rules (lowercase
    /// letters/digits/hyphens, 1-63 chars, no leading/trailing hyphen).
    public static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 63 else { return false }
        let pattern = "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}
