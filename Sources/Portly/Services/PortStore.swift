import Foundation
import Combine
import AppKit

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
    private var projectContextCache: [Int32: (projectName: String?, gitBranch: String?, workingDirectory: String?)] = [:]

    @Published var ignoredProcessNames: Set<String> = PortStore.loadIgnoredProcessNames()
    @Published var portLabels: [Int: String] = PortStore.loadPortLabels()
    @Published var hasAlert: Bool = false
    @Published private(set) var updatePhase: AutoUpdater.Phase = .idle

    private static let ignoredProcessNamesDefaultsKey = "ignoredProcessNames"
    private static let portLabelsDefaultsKey = "portLabels"

    func start() {
        NetworkThroughputResolver.shared.start()
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
        NetworkThroughputResolver.shared.stop()
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
                info.workingDirectory = context.workingDirectory
                info.uptimeSeconds = uptimes[info.pid]
                info.cpuPercent = metrics[info.pid]?.cpuPercent
                info.memPercent = metrics[info.pid]?.memPercent
                if let throughput = NetworkThroughputResolver.shared.throughput(for: info.pid) {
                    info.bytesInPerSecond = throughput.bytesInPerSecond
                    info.bytesOutPerSecond = throughput.bytesOutPerSecond
                }
                if let commandLine = commandLines[info.pid] {
                    info.commandLine = commandLine
                    info.frameworkLabel = FrameworkDetector.detect(
                        processName: info.processName, commandLine: commandLine
                    )
                }
                enriched.append(info)
            }

            let allEnriched = enriched
            await MainActor.run {
                let finalEnriched = allEnriched.filter {
                    !self.ignoredProcessNames.contains($0.processName.lowercased())
                }

                if self.hasCompletedInitialScan {
                    let diff = PortDiffer.diff(old: self.ports, new: finalEnriched, pinned: self.pinnedPorts)
                    diff.newPorts.forEach(NotificationManager.notifyNewPort)
                    if !diff.deadPinnedPorts.isEmpty {
                        diff.deadPinnedPorts.forEach(NotificationManager.notifyPinnedPortDied)
                        self.hasAlert = true
                    }
                }
                self.hasCompletedInitialScan = true

                self.ports = finalEnriched
                let livePids = Set(finalEnriched.map(\.pid))
                self.projectContextCache = self.projectContextCache.filter { livePids.contains($0.key) }
            }
        }
    }

    func clearAlert() {
        hasAlert = false
    }

    private func projectContext(for pid: Int32) async -> (projectName: String?, gitBranch: String?, workingDirectory: String?) {
        if let cached = await MainActor.run(body: { projectContextCache[pid] }) {
            return cached
        }
        let resolved = GitProjectResolver.resolve(pid: pid)
        let workingDirectory = GitProjectResolver.workingDirectory(of: pid)
        let combined = (resolved.projectName, resolved.gitBranch, workingDirectory)
        await MainActor.run { projectContextCache[pid] = combined }
        return combined
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

    /// Kills the process and relaunches its exact command line in the same working
    /// directory. Useful for bouncing a dev server without retyping the run command.
    func restart(_ info: PortInfo) {
        guard let commandLine = info.commandLine else { return }
        let workingDirectory = info.workingDirectory
        Darwin.kill(info.pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", commandLine]
            if let workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }
            try? process.run()
            self?.refresh()
        }
    }

    func ignoreProcessName(_ processName: String) {
        ignoredProcessNames.insert(processName.lowercased())
        UserDefaults.standard.set(Array(ignoredProcessNames), forKey: Self.ignoredProcessNamesDefaultsKey)
        refresh()
    }

    func unignoreProcessName(_ processName: String) {
        ignoredProcessNames.remove(processName.lowercased())
        UserDefaults.standard.set(Array(ignoredProcessNames), forKey: Self.ignoredProcessNamesDefaultsKey)
        refresh()
    }

    private static func loadIgnoredProcessNames() -> Set<String> {
        Set(UserDefaults.standard.array(forKey: ignoredProcessNamesDefaultsKey) as? [String] ?? [])
    }

    func setLabel(_ label: String, for port: Int) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            portLabels.removeValue(forKey: port)
        } else {
            portLabels[port] = trimmed
        }
        UserDefaults.standard.set(
            Dictionary(uniqueKeysWithValues: portLabels.map { (String($0.key), $0.value) }),
            forKey: Self.portLabelsDefaultsKey
        )
    }

    private static func loadPortLabels() -> [Int: String] {
        let raw = UserDefaults.standard.dictionary(forKey: portLabelsDefaultsKey) as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
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

    func installUpdate() {
        guard let update = availableUpdate, let dmgURL = update.dmgURL else {
            if let update = availableUpdate {
                NSWorkspace.shared.open(update.url)
            }
            return
        }
        Task {
            await AutoUpdater.downloadAndInstall(dmgURL: dmgURL, releasePageURL: update.url) { [weak self] phase in
                self?.updatePhase = phase
            }
        }
    }
}
