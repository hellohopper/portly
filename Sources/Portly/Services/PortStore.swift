import PortlyCore
import Foundation
import Combine
import AppKit

@MainActor
final class PortStore: ObservableObject {
    let history = HistoryStore()

    @Published private(set) var ports: [PortInfo] = []
    @Published private(set) var pinnedPorts: Set<Int> = PortStore.loadPinnedPorts()
    @Published private(set) var availableUpdate: UpdateChecker.UpdateInfo?

    private var timer: Timer?
    private let pollInterval: TimeInterval = 2.0
    private static let pinnedPortsDefaultsKey = "pinnedPorts"
    private var hasCompletedInitialScan = false
    /// Guards against overlapping scans (the 2s timer and user actions like kill/ignore
    /// each trigger their own refresh) applying results out of completion order -- only
    /// the most-recently-started scan's results are allowed to land.
    private var refreshGeneration = 0

    /// Git/project context rarely changes for the lifetime of a process, so cache it per pid
    /// instead of re-resolving (which shells out to lsof + reads files) on every poll.
    private var projectContextCache: [Int32: (projectName: String?, gitBranch: String?, workingDirectory: String?)] = [:]

    @Published var ignoredProcessNames: Set<String> = PortStore.loadIgnoredProcessNames()
    @Published var portLabels: [Int: String] = PortStore.loadPortLabels()
    @Published var proxyNames: [Int: String] = PortStore.loadProxyNames()
    @Published var isLocalhostProxyEnabled: Bool = PortStore.loadProxyEnabled() {
        didSet {
            guard isLocalhostProxyEnabled != oldValue else { return }
            UserDefaults.standard.set(isLocalhostProxyEnabled, forKey: Self.proxyEnabledDefaultsKey)
            if isLocalhostProxyEnabled {
                startLocalhostProxy()
            } else {
                proxyStartupError = nil
                LocalhostProxyServer.shared.stop()
            }
        }
    }
    /// Set when the proxy listener fails to bind (e.g. port 7777 already in use by
    /// something else) so Settings can tell the user instead of it silently doing nothing.
    @Published private(set) var proxyStartupError: String?
    @Published var hasAlert: Bool = false
    @Published private(set) var searchFocusRequestID = UUID()
    @Published private(set) var updatePhase: AutoUpdater.Phase = .idle
    /// port -> latest HTTP status code from the health probe (absent = not an HTTP server).
    @Published private(set) var healthStatuses: [Int: Int] = [:]
    /// port -> label contributed by a project's .portly.json; user labels take precedence.
    @Published private(set) var projectConfigLabels: [Int: String] = [:]

    /// The label to show for a port: the user's manual label wins over .portly.json.
    func effectiveLabel(for port: Int) -> String? {
        portLabels[port] ?? projectConfigLabels[port]
    }

    private static let ignoredProcessNamesDefaultsKey = "ignoredProcessNames"
    private static let portLabelsDefaultsKey = "portLabels"
    private static let proxyNamesDefaultsKey = "localhostProxyNames"
    private static let proxyEnabledDefaultsKey = "localhostProxyEnabled"

    func start() {
        NetworkThroughputResolver.shared.start()
        if isLocalhostProxyEnabled {
            startLocalhostProxy()
        }
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
        LocalhostProxyServer.shared.stop()
    }

    func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration

        Task.detached { [weak self] in
            let scanned = PortScanner.scan().sorted { $0.port < $1.port }
            guard let self else { return }

            let uniquePids = Array(Set(scanned.map(\.pid)))
            let uptimes = UptimeResolver.elapsedSeconds(for: uniquePids)
            let metrics = ProcessMetricsResolver.metrics(for: uniquePids)
            let commandLines = CommandLineResolver.commandLines(for: uniquePids)
            let processTable = ProcessTreeResolver.snapshot()

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
                info.ancestry = ProcessTreeResolver.ancestry(of: info.pid, in: processTable)
                enriched.append(info)
            }

            var configLabels: [Int: String] = [:]
            for directory in Set(enriched.compactMap(\.workingDirectory)) {
                // First project to label a port wins; overlaps across projects are rare.
                configLabels.merge(ProjectConfigResolver.shared.labels(fromDirectory: directory)) { current, _ in current }
            }
            let finalConfigLabels = configLabels

            let allEnriched = enriched
            await MainActor.run {
                // A newer refresh already started (and may have already landed its
                // results) -- applying this older, slower one now would go backwards.
                guard generation == self.refreshGeneration else { return }

                let finalEnriched = allEnriched.filter {
                    !self.ignoredProcessNames.contains($0.processName.lowercased())
                }

                if self.hasCompletedInitialScan {
                    let diff = PortDiffer.diff(old: self.ports, new: finalEnriched, pinned: self.pinnedPorts)
                    self.history.record(opened: diff.newPorts, closed: diff.closedPorts)
                    diff.newPorts.forEach(NotificationManager.notifyNewPort)
                    // A pinned port that vanished because its process was just added to
                    // the ignore list didn't actually die -- don't alert on those.
                    let trulyDead = diff.deadPinnedPorts.filter {
                        !self.ignoredProcessNames.contains($0.processName.lowercased())
                    }
                    if !trulyDead.isEmpty {
                        trulyDead.forEach(NotificationManager.notifyPinnedPortDied)
                        self.hasAlert = true
                    }
                }
                self.hasCompletedInitialScan = true

                self.ports = finalEnriched
                self.projectConfigLabels = finalConfigLabels
                let livePids = Set(finalEnriched.map(\.pid))
                self.projectContextCache = self.projectContextCache.filter { livePids.contains($0.key) }

                self.refreshHealthStatuses(for: finalEnriched)
                self.syncProxyRoutes()
            }
        }
    }

    private func refreshHealthStatuses(for ports: [PortInfo]) {
        let tcpPorts = ports.filter { $0.proto.contains("TCP") }.map(\.port)
        Task {
            let newStatuses = await HealthChecker.shared.statuses(for: tcpPorts)
            notifyHealthRegressions(old: healthStatuses, new: newStatuses, ports: ports)
            healthStatuses = newStatuses
        }
    }

    /// Notifies when a *pinned* port's HTTP status crosses into 5xx -- scoped to
    /// pinned ports (like the "pinned port died" alert) so a dev server's normal
    /// 404s on unrelated routes don't turn this into noise.
    private func notifyHealthRegressions(old: [Int: Int], new: [Int: Int], ports: [PortInfo]) {
        for (port, newStatus) in new {
            guard pinnedPorts.contains(port) else { continue }
            // No prior reading yet -- nothing to regress from.
            guard let oldStatus = old[port] else { continue }
            guard HealthChecker.Category.classify(statusCode: oldStatus) != .failing,
                  HealthChecker.Category.classify(statusCode: newStatus) == .failing else { continue }
            guard let info = ports.first(where: { $0.port == port }) else { continue }
            NotificationManager.notifyHealthRegression(info, statusCode: newStatus)
        }
    }

    func clearAlert() {
        hasAlert = false
    }

    /// A port from the common dev-server ranges (3000s/5000s/8000s) that nothing is
    /// currently listening on, per the latest scan.
    func suggestFreePort() -> Int? {
        FreePortFinder.suggest(excluding: Set(ports.map(\.port)))
    }

    /// Bumped each time the menu bar panel opens, so the view can refocus the
    /// search field even though it's the same SwiftUI hierarchy being re-shown
    /// (the popover's content view isn't recreated on each show).
    func requestSearchFocus() {
        searchFocusRequestID = UUID()
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

    /// Kills the process together with its wrapper ancestors (e.g. the `npm run dev`
    /// that spawned the `node` server), outermost first so nothing respawns the leaf.
    func killTree(_ info: PortInfo) {
        for entry in info.ancestry.reversed() {
            Darwin.kill(entry.pid, SIGTERM)
        }
        Darwin.kill(info.pid, SIGTERM)
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

    /// Sets (or, if `name` is empty, clears) the `.localhost` proxy name for a port.
    /// Rejects anything that isn't a valid DNS label rather than silently mangling it,
    /// so the caller can tell the user why their input didn't take.
    @discardableResult
    func setProxyName(_ name: String, for port: Int) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            proxyNames.removeValue(forKey: port)
        } else {
            guard LocalhostProxyServer.isValidName(trimmed) else { return false }
            proxyNames[port] = trimmed
        }
        UserDefaults.standard.set(
            Dictionary(uniqueKeysWithValues: proxyNames.map { (String($0.key), $0.value) }),
            forKey: Self.proxyNamesDefaultsKey
        )
        syncProxyRoutes()
        return true
    }

    private static func loadProxyNames() -> [Int: String] {
        let raw = UserDefaults.standard.dictionary(forKey: proxyNamesDefaultsKey) as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
    }

    private static func loadProxyEnabled() -> Bool {
        UserDefaults.standard.object(forKey: proxyEnabledDefaultsKey) as? Bool ?? false
    }

    private func startLocalhostProxy() {
        LocalhostProxyServer.shared.onStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .failed(let message):
                    self.proxyStartupError = message
                case .listening:
                    self.proxyStartupError = nil
                case .stopped:
                    break
                }
            }
        }
        LocalhostProxyServer.shared.start()
        syncProxyRoutes()
    }

    /// Pushes the current name -> port table to the proxy, dropping any name whose
    /// port isn't actually listening over TCP right now (a dead mapping would just
    /// dead-end the connection, but skipping it lets a *new* process on that name
    /// take over cleanly instead of racing a stale entry).
    private func syncProxyRoutes() {
        guard isLocalhostProxyEnabled else { return }
        let liveTCPPorts = Set(ports.filter { $0.proto.contains("TCP") }.map(\.port))
        var routes: [String: Int] = [:]
        for (port, name) in proxyNames where liveTCPPorts.contains(port) {
            routes[name] = port
        }
        LocalhostProxyServer.shared.updateRoutes(routes)
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
