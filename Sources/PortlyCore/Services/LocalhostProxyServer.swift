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

    private let routesLock = NSLock()
    private var routes: [String: Int] = [:]
    private var listener: NWListener?

    private init() {}

    /// Starts the listener if it isn't already running. Safe to call repeatedly.
    public func start() {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        // Bind loopback-only: this must never be reachable from the network, only
        // from the machine it's running on.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!
        )
        parameters.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: .global(qos: .utility))
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
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
        pipe(from: connection, to: upstream)
        pipe(from: upstream, to: connection)
    }

    private func pipe(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { _ in })
            }
            if isComplete || error != nil {
                destination.cancel()
                source.cancel()
                return
            }
            self?.pipe(from: source, to: destination)
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
