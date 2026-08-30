import PortlyCore
import Foundation
import Combine
import AppKit

@MainActor
final class PortStore: ObservableObject {
    let history = HistoryStore()

    @Published private(set) var ports: [PortInfo] = []
    /// The last scan before the ignore filter -- needed wherever "is this port taken?"
    /// must reflect reality rather than what the user chose to hide.
    private(set) var unfilteredPorts: [PortInfo] = []
    @Published private(set) var pinnedPorts: Set<Int> = Defaults.intSet(PortStore.pinnedPortsDefaultsKey)

    private var timer: Timer?
    /// The panel is closed the vast majority of the time, and a hidden list doesn't
    /// need second-by-second freshness -- but notifications and idle tracking still
    /// need *some* cadence, so back off rather than stopping.
    private static let visiblePollInterval: TimeInterval = 2.0
    private static let hiddenPollInterval: TimeInterval = 15.0
    private var pollInterval: TimeInterval = PortStore.hiddenPollInterval
    static let pinnedPortsDefaultsKey = "pinnedPorts"
    private var hasCompletedInitialScan = false
    /// Guards against overlapping scans (the 2s timer and user actions like kill/ignore
    /// each trigger their own refresh) applying results out of completion order -- only
    /// the most-recently-started scan's results are allowed to land.
    private var refreshGeneration = 0

    /// Git/project context rarely changes for the lifetime of a process, so cache it per pid
    /// instead of re-resolving (which shells out to lsof + reads files) on every poll.
    private var projectContextCache: [Int32: PortEnricher.ProjectContext] = [:]
    /// Set when a refresh is triggered by an ignore-list edit: the resulting diff is an
    /// artifact of the filter changing, not of ports actually opening or closing.
    private var suppressDiffNotificationsOnce = false

    @Published var ignoredProcessNames: Set<String> = Defaults.stringSet(PortStore.ignoredProcessNamesDefaultsKey)
    @Published var portLabels: [Int: String] = Defaults.intKeyedStrings(PortStore.portLabelsDefaultsKey)
    @Published var proxyNames: [Int: String] = Defaults.intKeyedStrings(PortStore.proxyNamesDefaultsKey)
    @Published var isLocalhostProxyEnabled: Bool = Defaults.bool(PortStore.proxyEnabledDefaultsKey) {
        didSet {
            guard isLocalhostProxyEnabled != oldValue else { return }
            Defaults.set(isLocalhostProxyEnabled, for: Self.proxyEnabledDefaultsKey)
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
    /// port -> latest health probe result (absent = not an HTTP server).
    @Published private(set) var healthResults: [Int: HealthChecker.Health] = [:]
    /// Merged `.portly.json` config from every project in the current scan.
    @Published private(set) var projectConfig = ProjectConfigResolver.Config()
    /// Ports a project declared but that nothing is listening on, or that a *different*
    /// project currently holds -- the "yesterday's server still owns 3000" case.
    @Published private(set) var portConflicts: [PortConflict] = []
    /// port -> label contributed by a project's .portly.json; user labels take precedence.
    @Published private(set) var projectConfigLabels: [Int: String] = [:]

    /// The label to show for a port: the user's manual label wins over .portly.json.
    func effectiveLabel(for port: Int) -> String? {
        PortLabelResolver.effectiveLabel(for: port, manual: portLabels, fromConfig: projectConfigLabels)
    }

    /// Whether a row survives the search field, labels included.
    func matchesSearch(_ info: PortInfo, needle: String) -> Bool {
        PortLabelResolver.matches(info, needle: needle, manual: portLabels, fromConfig: projectConfigLabels)
    }

    static let ignoredProcessNamesDefaultsKey = "ignoredProcessNames"
    static let portLabelsDefaultsKey = "portLabels"
    static let proxyNamesDefaultsKey = "localhostProxyNames"
    static let proxyEnabledDefaultsKey = "localhostProxyEnabled"

    func start() {
        NetworkThroughputResolver.shared.start()
        if isLocalhostProxyEnabled {
            startLocalhostProxy()
        }
        refresh()
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    /// Called when the menu bar panel opens or closes.
    func setPanelVisible(_ isVisible: Bool) {
        let interval = isVisible ? Self.visiblePollInterval : Self.hiddenPollInterval
        guard interval != pollInterval else { return }
        pollInterval = interval
        if isVisible { refresh() }
        // nettop exits on its own occasionally; opening the panel is a natural point
        // to notice and bring throughput sampling back.
        if NetworkThroughputResolver.shared.needsRestart {
            NetworkThroughputResolver.shared.start()
        }
        restartTimer()
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

            // Read the cache once, rather than hopping to the main actor per port.
            let contextCache = await MainActor.run { self.projectContextCache }
            let result = await PortEnricher.enrich(scanned, contextCache: contextCache)

            let allEnriched = result.ports
            let finalConfigLabels = result.projectConfigLabels
            let finalConfig = result.projectConfig
            let finalConfigsByRoot = result.configsByProjectRoot
            let finalRootByPort = result.projectRootByPort
            let newContexts = result.contextCache
            await MainActor.run {
                // A newer refresh already started (and may have already landed its
                // results) -- applying this older, slower one now would go backwards.
                guard generation == self.refreshGeneration else { return }

                self.projectContextCache = newContexts

                let finalEnriched = allEnriched.filter {
                    !self.ignoredProcessNames.contains($0.processName.lowercased())
                }

                // Diff against the *unfiltered* previous list, filtered the same way it
                // is now: otherwise adding a name to the ignore list reads as "those
                // ports all closed" (bogus history) and removing it reads as "brand new
                // ports" (a burst of notifications for servers running for hours).
                if self.hasCompletedInitialScan {
                    let diff = PortDiffer.diff(old: self.ports, new: finalEnriched, pinned: self.pinnedPorts)
                    if self.suppressDiffNotificationsOnce {
                        self.suppressDiffNotificationsOnce = false
                    } else {
                        self.history.record(
                            opened: diff.newPorts,
                            closed: diff.closedPorts,
                            replaced: diff.replacedPorts
                        )
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
                }
                self.hasCompletedInitialScan = true

                self.ports = finalEnriched
                self.unfilteredPorts = allEnriched
                self.projectConfigLabels = finalConfigLabels
                self.projectConfig = finalConfig
                self.portConflicts = PortConflictDetector.conflicts(
                    configsByProjectRoot: finalConfigsByRoot,
                    projectRootByPort: finalRootByPort,
                    ports: finalEnriched
                )

                self.refreshHealthStatuses(for: finalEnriched)
                self.syncProxyRoutes()
                self.trackIdlePorts(finalEnriched)
            }
        }
    }

    // MARK: - Idle port alerts

    @Published var isIdlePortAlertsEnabled: Bool = Defaults.bool(PortStore.idleAlertsEnabledDefaultsKey) {
        didSet {
            guard isIdlePortAlertsEnabled != oldValue else { return }
            Defaults.set(isIdlePortAlertsEnabled, for: Self.idleAlertsEnabledDefaultsKey)
            if !isIdlePortAlertsEnabled {
                idleState = IdlePortTracker.Snapshot()
            }
        }
    }
    /// Only consulted while `isIdlePortAlertsEnabled` is also on -- a separate toggle
    /// so turning on notifications never silently starts killing processes too.
    @Published var isIdlePortAutoKillEnabled: Bool = Defaults.bool(PortStore.idleAutoKillEnabledDefaultsKey) {
        didSet {
            guard isIdlePortAutoKillEnabled != oldValue else { return }
            Defaults.set(isIdlePortAutoKillEnabled, for: Self.idleAutoKillEnabledDefaultsKey)
        }
    }

    /// Off by default: the menu bar is contested real estate, so showing more than
    /// the icon has to be asked for.
    @Published var showsPinnedStatusInMenuBar: Bool = Defaults.bool(PortStore.menuBarStatusDefaultsKey) {
        didSet {
            guard showsPinnedStatusInMenuBar != oldValue else { return }
            Defaults.set(showsPinnedStatusInMenuBar, for: Self.menuBarStatusDefaultsKey)
        }
    }
    static let menuBarStatusDefaultsKey = "showsPinnedStatusInMenuBar"

    /// Worst health across pinned ports, for the menu bar icon: nil when nothing is
    /// pinned or nothing has been probed yet.
    var pinnedHealthSummary: HealthChecker.Category? {
        let categories = pinnedPorts.compactMap { healthResults[$0]?.category }
        guard !categories.isEmpty else { return nil }
        if categories.contains(.failing) { return .failing }
        if categories.contains(.warning) { return .warning }
        if categories.contains(.slow) { return .slow }
        return .healthy
    }

    static let idleAlertsEnabledDefaultsKey = "idlePortAlertsEnabled"
    static let idleAutoKillEnabledDefaultsKey = "idlePortAutoKillEnabled"
    private let idleTracker = IdlePortTracker()
    private var idleState = IdlePortTracker.Snapshot()

    private func trackIdlePorts(_ ports: [PortInfo]) {
        guard isIdlePortAlertsEnabled else { return }
        let result = idleTracker.advance(
            ports: ports,
            // Monotonic, so a sleep/wake cycle can't be mistaken for hours of silence.
            now: ProcessInfo.processInfo.systemUptime,
            hasThroughputData: NetworkThroughputResolver.shared.hasSamples,
            state: idleState
        )
        idleState = result.state

        for info in result.idle {
            if isIdlePortAutoKillEnabled {
                NotificationManager.notifyIdlePortKilled(info)
                kill(info)
            } else {
                NotificationManager.notifyIdlePort(info)
            }
        }
    }


    /// Probes run concurrently with the 2s poll, so without a generation guard a slow
    /// probe can resume after a newer one and overwrite fresher results -- which then
    /// re-fires the same regression alert on the next comparison.
    private var healthGeneration = 0

    private func refreshHealthStatuses(for ports: [PortInfo]) {
        let tcpPorts = ports.filter(\.isTCP).map(\.port)
        // Per-port probe targets: a project can point at its real health endpoint
        // instead of "/", and mark ports it serves over TLS.
        var targets: [Int: HealthChecker.Target] = [:]
        for port in tcpPorts {
            let target = projectConfig.healthTarget(for: port)
            if target != .default { targets[port] = target }
        }

        // Databases and other wire-protocol services never answer HTTP; probe those
        // with a raw TCP handshake instead of burning the HTTP timeout on them.
        let tcpOnlyLabels: Set<String> = ["Postgres", "Redis", "MySQL", "MongoDB"]
        let tcpOnlyPorts = Set(ports.filter { tcpOnlyLabels.contains($0.frameworkLabel ?? "") }.map(\.port))

        healthGeneration += 1
        let generation = healthGeneration
        Task {
            let newResults = await HealthChecker.shared.health(
                for: tcpPorts, targets: targets, tcpOnlyPorts: tcpOnlyPorts
            )
            guard generation == healthGeneration else { return }

            let regressed = HealthRegressionDetector.regressions(
                old: healthResults.compactMapValues(\.statusCode),
                new: newResults.compactMapValues(\.statusCode),
                pinned: pinnedPorts
            )
            healthResults = newResults
            for port in regressed {
                guard let info = ports.first(where: { $0.port == port }),
                      let result = newResults[port],
                      let statusCode = result.statusCode else { continue }
                NotificationManager.notifyHealthRegression(info, statusCode: statusCode)
            }
        }
    }

    func clearAlert() {
        hasAlert = false
    }

    /// A port from the common dev-server ranges (3000s/5000s/8000s) that nothing is
    /// currently listening on. Excludes ports held by *ignored* processes too --
    /// `ports` is the filtered list, so suggesting from it alone would happily hand
    /// back a port that a hidden process (commonly a Docker forward) already owns.
    func suggestFreePort() -> Int? {
        FreePortFinder.suggest(excluding: Set(unfilteredPorts.map(\.port)))
    }

    typealias ExportableProject = ProjectConfigExporter.Project

    /// Projects among the currently-listed ports that have at least one manual label,
    /// grouped by git root -- candidates to write/update a team-shared `.portly.json` for.
    func exportableProjects() -> [ExportableProject] {
        ProjectConfigExporter.exportableProjects(ports: ports, manualLabels: portLabels)
    }

    @discardableResult
    func exportProjectConfig(_ project: ExportableProject) -> URL? {
        ProjectConfigExporter.write(project)
    }

    /// Bumped each time the menu bar panel opens, so the view can refocus the
    /// search field even though it's the same SwiftUI hierarchy being re-shown
    /// (the popover's content view isn't recreated on each show).
    func requestSearchFocus() {
        searchFocusRequestID = UUID()
    }

    func kill(_ info: PortInfo) {
        kill([info])
    }

    func kill(_ infos: [PortInfo]) {
        // A Docker-forwarded port's pid is `com.docker.backend`, the host-side
        // forwarder shared by *every* container -- SIGTERMing it would either do
        // nothing visible or take down all Docker port forwarding, never the one
        // container the user meant. Route those through the daemon instead.
        let (containerised, native) = infos.reduce(into: ([String](), [PortInfo]())) { result, info in
            if info.isDockerManaged, let name = info.dockerContainerName {
                result.0.append(name)
            } else {
                result.1.append(info)
            }
        }

        terminate(native.map(\.pid))

        guard !containerised.isEmpty else { return }
        Task {
            for name in Set(containerised) {
                _ = await DockerContainerResolver.shared.stop(containerName: name)
            }
            refresh()
        }
    }

    /// Kills the process together with its wrapper ancestors (e.g. the `npm run dev`
    /// that spawned the `node` server), outermost first so nothing respawns the leaf.
    func killTree(_ info: PortInfo) {
        terminate(info.ancestry.reversed().map(\.pid) + [info.pid])
    }

    private func terminate(_ pids: [Int32]) {
        guard !pids.isEmpty else { return }
        for pid in pids {
            Darwin.kill(pid, SIGTERM)
        }
        // Give the processes a moment to exit, then refresh.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refresh()
        }
    }

    /// Kills the process and relaunches its exact command line in the same working
    /// directory. Useful for bouncing a dev server without retyping the run command.
    func restart(_ info: PortInfo) {
        if info.isDockerManaged, let containerName = info.dockerContainerName {
            Task {
                _ = await DockerContainerResolver.shared.restart(containerName: containerName)
                refresh()
            }
            return
        }

        guard let commandLine = info.commandLine else { return }
        let workingDirectory = info.workingDirectory

        Darwin.kill(info.pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            ProcessLauncher.launch(commandLine: commandLine, workingDirectory: workingDirectory)
            self?.refresh()
        }
    }

    /// Starts a port that has already closed, from what history recorded about it.
    /// `restart` can't do this: it needs a live process to read the command line from.
    @discardableResult
    func relaunch(_ event: HistoryStore.Event) -> Bool {
        guard let commandLine = event.commandLine else { return false }
        let launched = ProcessLauncher.launch(
            commandLine: commandLine, workingDirectory: event.workingDirectory
        )
        if launched {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.refresh()
            }
        }
        return launched
    }

    func ignoreProcessName(_ processName: String) {
        ignoredProcessNames.insert(processName.lowercased())
        Defaults.set(ignoredProcessNames, for: Self.ignoredProcessNamesDefaultsKey)
        // Hiding rows needs no rescan: the answer is already in `unfilteredPorts`, and
        // re-running the whole pipeline just to drop rows is wasted work. Reapplying
        // the filter locally also avoids a diff that reads as "those ports closed".
        applyIgnoreFilter()
    }

    func unignoreProcessName(_ processName: String) {
        ignoredProcessNames.remove(processName.lowercased())
        Defaults.set(ignoredProcessNames, for: Self.ignoredProcessNamesDefaultsKey)
        // Un-hiding can reveal ports the last scan didn't retain details for, so this
        // direction does need fresh data -- but the reappearing rows have been running
        // all along and must not be announced as new.
        suppressDiffNotificationsOnce = true
        refresh()
    }

    /// Re-derives the visible list from the last scan, without rescanning.
    private func applyIgnoreFilter() {
        ports = unfilteredPorts.filter { !ignoredProcessNames.contains($0.processName.lowercased()) }
        syncProxyRoutes()
    }


    func setLabel(_ label: String, for port: Int) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            portLabels.removeValue(forKey: port)
        } else {
            portLabels[port] = trimmed
        }
        Defaults.set(portLabels, for: Self.portLabelsDefaultsKey)
    }


    enum ProxyNameError: Equatable {
        case invalid
        case alreadyUsed(port: Int)
    }

    /// Sets (or, if `name` is empty, clears) the `.localhost` proxy name for a port.
    /// Rejects anything that isn't a valid DNS label, and anything already claimed by
    /// another port -- two ports sharing a name would leave which server
    /// `name.localhost` reaches down to dictionary ordering, flipping between refreshes.
    @discardableResult
    func setProxyName(_ name: String, for port: Int) -> ProxyNameError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            proxyNames.removeValue(forKey: port)
        } else {
            guard LocalhostProxyServer.isValidName(trimmed) else { return .invalid }
            if let conflicting = proxyNames.first(where: { $0.value == trimmed && $0.key != port }) {
                return .alreadyUsed(port: conflicting.key)
            }
            proxyNames[port] = trimmed
        }
        Defaults.set(proxyNames, for: Self.proxyNamesDefaultsKey)
        syncProxyRoutes()
        return nil
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
        LocalhostProxyServer.shared.updateRoutes(
            LocalhostProxyServer.routes(names: proxyNames, livePorts: ports)
        )
    }

    func togglePin(_ port: Int) {
        if pinnedPorts.contains(port) {
            pinnedPorts.remove(port)
        } else {
            pinnedPorts.insert(port)
        }
        Defaults.set(pinnedPorts, for: Self.pinnedPortsDefaultsKey)
    }


}
