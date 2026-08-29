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
    @Published private(set) var pinnedPorts: Set<Int> = PortStore.loadPinnedPorts()
    @Published private(set) var availableUpdate: UpdateChecker.UpdateInfo?

    private var timer: Timer?
    /// The panel is closed the vast majority of the time, and a hidden list doesn't
    /// need second-by-second freshness -- but notifications and idle tracking still
    /// need *some* cadence, so back off rather than stopping.
    private static let visiblePollInterval: TimeInterval = 2.0
    private static let hiddenPollInterval: TimeInterval = 15.0
    private var pollInterval: TimeInterval = PortStore.hiddenPollInterval
    private static let pinnedPortsDefaultsKey = "pinnedPorts"
    private var hasCompletedInitialScan = false
    /// Guards against overlapping scans (the 2s timer and user actions like kill/ignore
    /// each trigger their own refresh) applying results out of completion order -- only
    /// the most-recently-started scan's results are allowed to land.
    private var refreshGeneration = 0

    /// Git/project context rarely changes for the lifetime of a process, so cache it per pid
    /// instead of re-resolving (which shells out to lsof + reads files) on every poll.
    private var projectContextCache: [Int32: ProjectContext] = [:]
    /// Set when a refresh is triggered by an ignore-list edit: the resulting diff is an
    /// artifact of the filter changing, not of ports actually opening or closing.
    private var suppressDiffNotificationsOnce = false

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

            let uniquePids = Array(Set(scanned.map(\.pid)))
            // One `ps -axo` covers uptime, %CPU, %MEM and the ancestry table; only the
            // full command line (whose argv contains spaces) needs its own call.
            let table = ProcessTable.snapshot()
            let uptimes = table.uptimeSeconds(for: uniquePids)
            let metrics = table.metrics(for: uniquePids)
            let commandLines = CommandLineResolver.commandLines(for: uniquePids)
            let processTable = table.ancestryTable

            // Reading the cache once, rather than hopping to the main actor per port.
            let contextCache = await MainActor.run { self.projectContextCache }
            var resolvedContexts = contextCache

            var enriched: [PortInfo] = []
            enriched.reserveCapacity(scanned.count)
            for var info in scanned {
                let context = Self.projectContext(
                    for: info.pid,
                    startedAt: table.startTime(of: info.pid),
                    cache: &resolvedContexts
                )
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
                info.throughputHistory = NetworkThroughputResolver.shared.history(for: info.pid)
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

            let dockerPorts = enriched.filter(\.isDockerManaged).map(\.port)
            let containerNames = await DockerContainerResolver.shared.containerNames(for: dockerPorts)
            for index in enriched.indices {
                enriched[index].dockerContainerName = containerNames[enriched[index].port]
            }

            let allEnriched = enriched
            let newContexts = resolvedContexts
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

                self.refreshHealthStatuses(for: finalEnriched)
                self.syncProxyRoutes()
                self.trackIdlePorts(finalEnriched)
            }
        }
    }

    // MARK: - Idle port alerts

    @Published var isIdlePortAlertsEnabled: Bool = PortStore.loadBool(PortStore.idleAlertsEnabledDefaultsKey) {
        didSet {
            guard isIdlePortAlertsEnabled != oldValue else { return }
            UserDefaults.standard.set(isIdlePortAlertsEnabled, forKey: Self.idleAlertsEnabledDefaultsKey)
            if !isIdlePortAlertsEnabled {
                idleState = IdlePortTracker.Snapshot()
            }
        }
    }
    /// Only consulted while `isIdlePortAlertsEnabled` is also on -- a separate toggle
    /// so turning on notifications never silently starts killing processes too.
    @Published var isIdlePortAutoKillEnabled: Bool = PortStore.loadBool(PortStore.idleAutoKillEnabledDefaultsKey) {
        didSet {
            guard isIdlePortAutoKillEnabled != oldValue else { return }
            UserDefaults.standard.set(isIdlePortAutoKillEnabled, forKey: Self.idleAutoKillEnabledDefaultsKey)
        }
    }

    private static let idleAlertsEnabledDefaultsKey = "idlePortAlertsEnabled"
    private static let idleAutoKillEnabledDefaultsKey = "idlePortAutoKillEnabled"
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

    private static func loadBool(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? false
    }

    /// Probes run concurrently with the 2s poll, so without a generation guard a slow
    /// probe can resume after a newer one and overwrite fresher results -- which then
    /// re-fires the same regression alert on the next comparison.
    private var healthGeneration = 0

    private func refreshHealthStatuses(for ports: [PortInfo]) {
        let tcpPorts = ports.filter(\.isTCP).map(\.port)
        healthGeneration += 1
        let generation = healthGeneration
        Task {
            let newStatuses = await HealthChecker.shared.statuses(for: tcpPorts)
            guard generation == healthGeneration else { return }

            let regressed = HealthRegressionDetector.regressions(
                old: healthStatuses, new: newStatuses, pinned: pinnedPorts
            )
            healthStatuses = newStatuses
            for port in regressed {
                guard let info = ports.first(where: { $0.port == port }),
                      let status = newStatuses[port] else { continue }
                NotificationManager.notifyHealthRegression(info, statusCode: status)
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

    struct ExportableProject: Identifiable {
        let root: URL
        let labels: [Int: String]
        var id: String { root.path }
        var name: String { root.lastPathComponent }
    }

    /// Projects among the currently-listed ports that have at least one manual label,
    /// grouped by git root -- candidates to write/update a team-shared `.portly.json` for.
    func exportableProjects() -> [ExportableProject] {
        var byRoot: [URL: [Int: String]] = [:]
        for info in ports {
            guard let label = portLabels[info.port], let workingDirectory = info.workingDirectory else { continue }
            let root = GitProjectResolver.projectRoot(fromDirectory: workingDirectory)
            byRoot[root, default: [:]][info.port] = label
        }
        return byRoot.map { ExportableProject(root: $0.key, labels: $0.value) }
            .sorted { $0.name < $1.name }
    }

    /// Writes `.portly.json` at `project.root`, merging the manual labels in over
    /// whatever the file already has (manual labels already win when reading, so this
    /// keeps that same precedence rather than clobbering entries the file previously
    /// had for ports that aren't currently listening).
    @discardableResult
    func exportProjectConfig(_ project: ExportableProject) -> URL? {
        let configURL = project.root.appendingPathComponent(".portly.json")
        var merged = ProjectConfigResolver.shared.labels(fromDirectory: project.root.path)
        merged.merge(project.labels) { _, manual in manual }

        let payload: [String: Any] = [
            "labels": Dictionary(uniqueKeysWithValues: merged.map { (String($0.key), $0.value) })
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        do {
            try data.write(to: configURL)
            return configURL
        } catch {
            return nil
        }
    }

    /// Bumped each time the menu bar panel opens, so the view can refocus the
    /// search field even though it's the same SwiftUI hierarchy being re-shown
    /// (the popover's content view isn't recreated on each show).
    func requestSearchFocus() {
        searchFocusRequestID = UUID()
    }

    /// Resolves a process's project context, memoised for the lifetime of that
    /// process. The cache is validated against the process's *start time* as well as
    /// its pid: after pid reuse the number alone would hand a brand new process the
    /// dead one's project, branch, and working directory -- which would then send
    /// "open in editor" and quick-restart to the wrong repository.
    nonisolated private static func projectContext(
        for pid: Int32,
        startedAt: TimeInterval?,
        cache: inout [Int32: ProjectContext]
    ) -> ProjectContext {
        // `ps` reports elapsed time in whole seconds, so the derived start time can
        // wobble by a second between snapshots for the same process.
        if let cached = cache[pid], Self.isSameProcess(cached.startTime, startedAt) {
            return cached
        }
        // One lsof for the cwd, then pure filesystem reads from there -- resolving the
        // pid twice used to spawn lsof once per call.
        let workingDirectory = GitProjectResolver.workingDirectory(of: pid)
        let resolved = workingDirectory.map(GitProjectResolver.resolve(workingDirectory:))
        let context = ProjectContext(
            projectName: resolved?.projectName,
            gitBranch: resolved?.gitBranch,
            workingDirectory: workingDirectory,
            startTime: startedAt
        )
        cache[pid] = context
        return context
    }

    nonisolated private static func isSameProcess(_ cached: TimeInterval?, _ current: TimeInterval?) -> Bool {
        guard let cached, let current else { return cached == nil && current == nil }
        return abs(cached - current) <= 2
    }

    struct ProjectContext {
        let projectName: String?
        let gitBranch: String?
        let workingDirectory: String?
        /// Seconds-since-boot at which the process started, as of caching. A pid whose
        /// start time has moved is a *different* process that happens to reuse the number.
        let startTime: TimeInterval?
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
        // `ps -o command=` joins argv with spaces and no quoting, so handing it to
        // `sh -c` would re-split arguments that contained spaces, glob-expand `*`, and
        // interpret `;`/`&&`/`$`. Exec the argv directly instead: worst case an
        // argument that genuinely contained a space stays split, which is far better
        // than the shell running something the user never typed.
        let argv = commandLine.split(separator: " ").map(String.init)
        guard let executable = argv.first else { return }
        let workingDirectory = info.workingDirectory

        Darwin.kill(info.pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let process = Process()
            if executable.hasPrefix("/") {
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = Array(argv.dropFirst())
            } else {
                // A bare name (e.g. "node") needs PATH resolution, which Process
                // doesn't do; env does, without involving a shell.
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = argv
            }
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
        // The ports about to disappear from the list are being hidden, not closed.
        suppressDiffNotificationsOnce = true
        refresh()
    }

    func unignoreProcessName(_ processName: String) {
        ignoredProcessNames.remove(processName.lowercased())
        UserDefaults.standard.set(Array(ignoredProcessNames), forKey: Self.ignoredProcessNamesDefaultsKey)
        // Likewise: these have been running all along, they were just filtered out.
        suppressDiffNotificationsOnce = true
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
        UserDefaults.standard.set(
            Dictionary(uniqueKeysWithValues: proxyNames.map { (String($0.key), $0.value) }),
            forKey: Self.proxyNamesDefaultsKey
        )
        syncProxyRoutes()
        return nil
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
