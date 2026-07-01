import Foundation
import Combine

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var ports: [PortInfo] = []
    @Published private(set) var pinnedPorts: Set<Int> = PortStore.loadPinnedPorts()
    @Published private(set) var availableUpdate: UpdateChecker.UpdateInfo?

    private var timer: Timer?
    private let pollInterval: TimeInterval = 2.0
    private static let pinnedPortsDefaultsKey = "pinnedPorts"
    private var hasCompletedInitialScan = false

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

            let uniquePids = Array(Set(scanned.map(\.pid)))
            let uptimes = UptimeResolver.elapsedSeconds(for: uniquePids)
            let metrics = ProcessMetricsResolver.metrics(for: uniquePids)
            let commandLines = CommandLineResolver.commandLines(for: uniquePids)

            var enriched: [PortInfo] = []
            enriched.reserveCapacity(scanned.count)
            for var info in scanned {
                let context = await self.projectContext(for: info.pid)
                info.projectName = context.projectName
                info.gitBranch = context.gitBranch
                info.uptimeSeconds = uptimes[info.pid]
                info.cpuPercent = metrics[info.pid]?.cpuPercent
                info.memPercent = metrics[info.pid]?.memPercent
                if let commandLine = commandLines[info.pid] {
                    info.frameworkLabel = FrameworkDetector.detect(
                        processName: info.processName, commandLine: commandLine
                    )
                }
                enriched.append(info)
            }

            let finalEnriched = enriched
            await MainActor.run {
                if self.hasCompletedInitialScan {
                    let diff = PortDiffer.diff(old: self.ports, new: finalEnriched, pinned: self.pinnedPorts)
                    diff.newPorts.forEach(NotificationManager.notifyNewPort)
                    diff.deadPinnedPorts.forEach(NotificationManager.notifyPinnedPortDied)
                }
                self.hasCompletedInitialScan = true

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

    func kill(_ infos: [PortInfo]) {
        for info in infos {
            Darwin.kill(info.pid, SIGTERM)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refresh()
        }
    }

    func togglePin(_ port: Int) {
        if pinnedPorts.contains(port) {
            pinnedPorts.remove(port)
        } else {
            pinnedPorts.insert(port)
        }
        UserDefaults.standard.set(Array(pinnedPorts), forKey: Self.pinnedPortsDefaultsKey)
    }

    private static func loadPinnedPorts() -> Set<Int> {
        Set(UserDefaults.standard.array(forKey: pinnedPortsDefaultsKey) as? [Int] ?? [])
    }

    func checkForUpdate() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        Task {
            self.availableUpdate = await UpdateChecker.checkForUpdate(currentVersion: currentVersion)
        }
    }
}
