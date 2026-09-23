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
        guard let cloudflared = Self.cloudflaredPath else {
            tunnels[port] = .failed("cloudflared isn't installed. Run `brew install cloudflared`.")
            return
        }

        tunnels[port] = .starting

        let process = Process()
        // Resolved against the user's shell PATH: launched from Finder, the app's own
        // PATH doesn't include Homebrew, so `/usr/bin/env cloudflared` never found it.
        process.executableURL = URL(fileURLWithPath: cloudflared)
        process.arguments = ["tunnel", "--url", "http://localhost:\(port)"]
        process.environment = ExecutableResolver.environment()

        let pipe = Pipe()
        // cloudflared logs (including the assigned URL) go to stderr; merge both so
        // nothing is missed regardless of which stream it lands on.
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // EOF: without detaching, Foundation re-invokes this handler in a tight
            // loop until the termination handler gets around to it.
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
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

    /// Not cached: `brew install cloudflared` after a failed attempt should work
    /// without relaunching Portly, and a lookup is only a few `stat`s.
    private static var cloudflaredPath: String? {
        ExecutableResolver.resolve("cloudflared")
    }

    /// cloudflared prints its assigned hostname inside a bordered banner, e.g.
    /// "https://random-words-1234.trycloudflare.com".
    nonisolated static func extractURL(from text: String) -> String? {
        let pattern = #"https://[a-zA-Z0-9-]+\.trycloudflare\.com"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}
