import Foundation
import Combine

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var ports: [PortInfo] = []

    private var timer: Timer?
    private let pollInterval: TimeInterval = 2.0

    /// Git/project context rarely changes for the lifetime of a process, so cache it per pid
    /// instead of re-resolving (which shells out to lsof + reads files) on every poll.
    private var projectContextCache: [Int32: (projectName: String?, gitBranch: String?)] = [:]

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        Task.detached { [weak self] in
            let scanned = PortScanner.scan().sorted { $0.port < $1.port }
            guard let self else { return }

            var enriched: [PortInfo] = []
            enriched.reserveCapacity(scanned.count)
            for var info in scanned {
                let context = await self.projectContext(for: info.pid)
                info.projectName = context.projectName
                info.gitBranch = context.gitBranch
                enriched.append(info)
            }

            let finalEnriched = enriched
            await MainActor.run {
                self.ports = finalEnriched
                let livePids = Set(finalEnriched.map(\.pid))
                self.projectContextCache = self.projectContextCache.filter { livePids.contains($0.key) }
            }
        }
    }

    private func projectContext(for pid: Int32) async -> (projectName: String?, gitBranch: String?) {
        if let cached = await MainActor.run(body: { projectContextCache[pid] }) {
            return cached
        }
        let resolved = GitProjectResolver.resolve(pid: pid)
        await MainActor.run { projectContextCache[pid] = resolved }
        return resolved
    }

    func kill(_ info: PortInfo) {
        Darwin.kill(info.pid, SIGTERM)
        // Give the process a moment to exit, then refresh.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refresh()
        }
    }
}
