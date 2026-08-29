import PortlyCore
import SwiftUI
import AppKit

struct PortRow: View {
    let info: PortInfo
    @ObservedObject var store: PortStore
    let isSelecting: Bool
    let isSelected: Bool
    let isFocused: Bool
    let onToggleSelect: () -> Void

    // Everything below used to be passed in as a separate parameter; they are all
    // plain lookups on the store, and keeping fifteen of them in sync at the call
    // site was pure overhead.
    private var isPinned: Bool { store.pinnedPorts.contains(info.port) }
    private var label: String? { store.effectiveLabel(for: info.port) }
    private var health: HealthChecker.Health? { store.healthResults[info.port] }
    private var proxyName: String? { store.proxyNames[info.port] }
    private var isProxyEnabled: Bool { store.isLocalhostProxyEnabled }

    private func onKill() { store.kill(info) }
    private func onKillTree() { store.killTree(info) }
    private func onTogglePin() { store.togglePin(info.port) }
    private func onRestart() { store.restart(info) }
    private func onIgnore() { store.ignoreProcessName(info.processName) }
    private func onSetLabel(_ value: String) { store.setLabel(value, for: info.port) }
    private func onSetProxyName(_ value: String) -> PortStore.ProxyNameError? {
        store.setProxyName(value, for: info.port)
    }

    @State private var isEditingLabel = false
    @State private var labelText = ""
    @State private var isEditingProxyName = false
    @State private var proxyNameText = ""
    @State private var isShowingPeers = false
    @State private var isLoadingPeers = false
    @State private var peers: [ConnectionResolver.Peer] = []
    @State private var showsNoLogAlert = false

    var body: some View {
        HStack {
            if isSelecting {
                Button(action: onToggleSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: "\(info.port)")
                        .font(.system(.body, design: .monospaced).bold())
                    if let health {
                        Text(verbatim: "\(health.statusCode)")
                            .font(.system(.caption2, design: .monospaced).bold())
                            .foregroundStyle(healthColor(for: health.category))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(healthColor(for: health.category).opacity(0.15))
                            .clipShape(Capsule())
                            .help(healthTooltip(health))
                    }
                    if info.isExposedToNetwork {
                        Text("LAN")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                            .help("Bound to all interfaces (\(info.bindAddress ?? "*")) — reachable by anyone on your network")
                    }
                    if info.isDockerManaged {
                        Image(systemName: "shippingbox.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .help(info.dockerContainerName.map { "Docker container: \($0)" }
                                  ?? "Container-mapped port (Docker)")
                    }
                    if let dockerContainerName = info.dockerContainerName {
                        Text(dockerContainerName)
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    if let projectName = info.projectName {
                        Text(projectLabel(name: projectName, branch: info.gitBranch))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Button(action: beginEditingLabel) {
                        Image(systemName: "pencil")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Add a custom label")
                    .popover(isPresented: $isEditingLabel) {
                        InlineEditPopover(
                            placeholder: "Label",
                            text: $labelText,
                            onCommit: commitLabel
                        )
                    }
                    if isProxyEnabled && info.isTCP {
                        Button(action: beginEditingProxyName) {
                            Image(systemName: "globe")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("Give this port a name.localhost address")
                        .popover(isPresented: $isEditingProxyName) {
                            InlineEditPopover(
                                placeholder: "name",
                                suffix: ".localhost:\(LocalhostProxyServer.port)",
                                fieldWidth: 120,
                                text: $proxyNameText,
                                onCommit: commitProxyName
                            )
                        }
                    }
                }
                if let label {
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
                if let proxyName {
                    Button(action: openProxyURL) {
                        Text("\(proxyName).localhost:\(LocalhostProxyServer.port)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in browser")
                }
                Text(verbatim: primaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(info.ancestry.isEmpty
                          ? ""
                          : "Process tree: \(ProcessTreeResolver.describe(leafName: info.processName, ancestry: info.ancestry))")
                if let secondaryLine {
                    HStack(spacing: 4) {
                        Text(verbatim: secondaryLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let cpuPercent = info.cpuPercent {
                            Circle()
                                .fill(energyColor(for: cpuPercent))
                                .frame(width: 6, height: 6)
                                .help("Energy impact (based on CPU usage)")
                        }
                        if info.throughputHistory.contains(where: { $0 > 0 }) {
                            Sparkline(samples: info.throughputHistory)
                                .frame(width: 40, height: 12)
                                .help("Network throughput, last ~40s")
                        }
                    }
                }
            }
            Spacer()
            PortRowActions(
                info: info,
                isPinned: isPinned,
                onTogglePin: onTogglePin,
                onRestart: onRestart,
                onKill: onKill,
                onOpenInBrowser: openInBrowser
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isFocused ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting { onToggleSelect() }
        }
        .contextMenu {
            Button("Copy localhost URL") { copyLocalhostURL() }
            if let proxyName {
                Button("Copy .localhost URL") { copyToPasteboard(proxyURLString(name: proxyName)) }
            }
            if info.isTCP {
                Button("Copy as curl") { copyToPasteboard(CurlCommandBuilder.command(port: info.port)) }
                Button("Show connected clients") { loadPeers() }
            }
            if let containerName = info.dockerContainerName {
                Button("Copy docker logs command") {
                    copyToPasteboard("docker logs -f \(containerName)")
                }
            } else {
                Button("Open log file") { openLogFile() }
            }
            if !info.ancestry.isEmpty {
                Button("Kill process tree (\(ProcessTreeResolver.describe(leafName: info.processName, ancestry: info.ancestry)))",
                       role: .destructive, action: onKillTree)
            }
            Button("Ignore \(info.processName)", action: onIgnore)
        }
        .popover(isPresented: $isShowingPeers) {
            PeersPopover(port: info.port, peers: peers, isLoading: isLoadingPeers)
        }
        .alert("No log file found", isPresented: $showsNoLogAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(info.processName) isn't writing to a log file Portly can see — a server running in the foreground writes to its terminal instead.")
        }
    }

    private func loadPeers() {
        isLoadingPeers = true
        isShowingPeers = true
        let port = info.port
        Task {
            // Runs its own lsof, so it stays off the 2s poll and only happens on ask.
            let found = await Task.detached {
                ConnectionResolver.peers(forPort: port, processTable: [:])
            }.value
            peers = found
            isLoadingPeers = false
        }
    }

    private func openLogFile() {
        let pid = info.pid
        let workingDirectory = info.workingDirectory
        Task {
            let path = await Task.detached {
                LogFileResolver.logFile(pid: pid, workingDirectory: workingDirectory)
            }.value
            guard let path else {
                showsNoLogAlert = true
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    private func beginEditingLabel() {
        labelText = label ?? ""
        isEditingLabel = true
    }

    /// Labels accept anything, so this never reports an error.
    private func commitLabel() -> String? {
        onSetLabel(labelText)
        isEditingLabel = false
        return nil
    }

    private func beginEditingProxyName() {
        proxyNameText = proxyName ?? ""
        isEditingProxyName = true
    }

    private func commitProxyName() -> String? {
        switch onSetProxyName(proxyNameText) {
        case nil:
            isEditingProxyName = false
            return nil
        case .invalid:
            return "Lowercase letters, digits, hyphens only."
        case .alreadyUsed(let port):
            return "Already used by port \(port)."
        }
    }

    private func proxyURLString(name: String) -> String {
        "http://\(name).localhost:\(LocalhostProxyServer.port)"
    }

    private func openProxyURL() {
        guard let proxyName, let url = URL(string: proxyURLString(name: proxyName)) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openInBrowser() {
        guard let url = URL(string: "http://localhost:\(info.port)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyLocalhostURL() {
        copyToPasteboard("http://localhost:\(info.port)")
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func projectLabel(name: String, branch: String?) -> String {
        guard let branch else { return name }
        return "\(name)·\(branch)"
    }

    private var primaryLine: String {
        var parts = [info.frameworkLabel ?? info.processName, "pid \(info.pid)", info.proto]
        if let uptimeSeconds = info.uptimeSeconds {
            parts.append(UptimeResolver.format(uptimeSeconds))
        }
        return parts.joined(separator: " · ")
    }

    private var secondaryLine: String? {
        guard let cpuPercent = info.cpuPercent, let memPercent = info.memPercent else { return nil }
        var line = String(format: "CPU %.0f%% · MEM %.0f%%", cpuPercent, memPercent)
        if let bytesIn = info.bytesInPerSecond, let bytesOut = info.bytesOutPerSecond, bytesIn + bytesOut > 0 {
            line += " · ↓\(ByteRateFormatter.format(bytesPerSecond: bytesIn)) ↑\(ByteRateFormatter.format(bytesPerSecond: bytesOut))"
        }
        return line
    }

    private func energyColor(for cpuPercent: Double) -> Color {
        switch ProcessMetricsResolver.EnergyLevel.from(cpuPercent: cpuPercent) {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }

    private func healthColor(for category: HealthChecker.Category) -> Color {
        switch category {
        case .healthy: return .green
        case .slow: return .yellow
        case .warning: return .orange
        case .failing: return .red
        }
    }

    private func healthTooltip(_ health: HealthChecker.Health) -> String {
        let probed = store.projectConfig.healthTarget(for: info.port)
        let scheme = probed.useTLS ? "https" : "http"
        let millis = Int((health.latency * 1000).rounded())
        var text = "HTTP \(health.statusCode) in \(millis)ms from \(scheme)://localhost:\(info.port)\(probed.path)"
        if health.category == .slow {
            text += " — responding, but slowly"
        }
        return text
    }
}

/// A tiny filled line chart of recent throughput samples, oldest first.
