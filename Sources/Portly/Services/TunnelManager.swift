import Foundation
import PortlyCore

/// Shares a local port over the internet via a Cloudflare quick tunnel
/// (`cloudflared tunnel --url ...`) -- no account, no config file, no DNS to set up.
/// Requires `cloudflared` on PATH (`brew install cloudflared`); Portly never bundles
/// or installs it.
@MainActor
final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()

    enum State: Equatable {
        case starting
        case running(url: String)
        case failed(String)
    }

    @Published private(set) var tunnels: [Int: State] = [:]
    private var processes: [Int: Process] = [:]

    private init() {}

    func start(port: Int) {
        guard tunnels[port] == nil || isFailed(port) else { return }
        guard Self.isCloudflaredAvailable else {
            tunnels[port] = .failed("cloudflared isn't installed. Run `brew install cloudflared`.")
            return
        }

        tunnels[port] = .starting

        let process = Process()
        // `cloudflared` needs PATH resolution, which Process.executableURL doesn't do.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["cloudflared", "tunnel", "--url", "http://localhost:\(port)"]

        let pipe = Pipe()
        // cloudflared logs (including the assigned URL) go to stderr; merge both so
        // nothing is missed regardless of which stream it lands on.
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            guard let url = Self.extractURL(from: chunk) else { return }
            Task { @MainActor in
                guard self?.processes[port] != nil else { return } // stopped in the meantime
                self?.tunnels[port] = .running(url: url)
            }
        }

        process.terminationHandler = { [weak self] terminated in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard self?.processes[port] === terminated else { return } // superseded by a newer start()
                self?.processes[port] = nil
                if case .running = self?.tunnels[port] {
                    self?.tunnels[port] = .failed("Tunnel closed.")
                } else if self?.tunnels[port] == .starting {
                    self?.tunnels[port] = .failed("cloudflared exited before a tunnel URL appeared.")
                }
            }
        }

        do {
            try process.run()
            processes[port] = process
        } catch {
            tunnels[port] = .failed("Couldn't start cloudflared: \(error.localizedDescription)")
        }
    }

    func stop(port: Int) {
        processes[port]?.terminationHandler = nil
        processes[port]?.terminate()
        processes[port] = nil
        tunnels[port] = nil
    }

    func stopAll() {
        for port in processes.keys { stop(port: port) }
    }

    private func isFailed(_ port: Int) -> Bool {
        if case .failed = tunnels[port] { return true }
        return false
    }

    private static let isCloudflaredAvailable: Bool = {
        Shell.succeeds("/usr/bin/env", ["cloudflared", "--version"])
    }()

    /// cloudflared prints its assigned hostname inside a bordered banner, e.g.
    /// "https://random-words-1234.trycloudflare.com".
    nonisolated static func extractURL(from text: String) -> String? {
        let pattern = #"https://[a-zA-Z0-9-]+\.trycloudflare\.com"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}
