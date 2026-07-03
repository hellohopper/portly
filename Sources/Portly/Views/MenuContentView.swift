import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: PortStore
    let onHotkeyChange: (UInt32, UInt32) -> Void
    @AppStorage("appTheme") private var themeRawValue: String = AppTheme.system.rawValue
    @State private var searchText: String = ""
    @State private var isSelecting: Bool = false
    @State private var selectedPorts: Set<Int> = []
    @State private var isSettingsPresented: Bool = false
    @State private var isHistoryPresented: Bool = false

    private var theme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    private var filteredPorts: [PortInfo] {
        store.ports.filter { matchesSearch($0) }
    }

    private func matchesSearch(_ info: PortInfo) -> Bool {
        if info.matches(query: searchText) { return true }
        // Labels (manual or .portly.json) live in the store keyed by port, not on
        // PortInfo, so they need their own check to be searchable.
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty, let label = store.effectiveLabel(for: info.port) else { return false }
        return label.lowercased().contains(needle)
    }

    private var sections: [PortGrouping.Section] {
        PortGrouping.sections(for: filteredPorts, pinned: store.pinnedPorts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let update = store.availableUpdate {
                updateBanner(update)
                Divider()
            }

            if store.ports.isEmpty {
                Text("No listening ports")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                searchField
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                Divider()

                if filteredPorts.isEmpty {
                    Text("No ports match \"\(searchText)\"")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ScrollView {
                        ForEach(sections) { section in
                            Text(section.title.uppercased())
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 2)

                            ForEach(section.ports) { port in
                                PortRow(
                                    info: port,
                                    isPinned: store.pinnedPorts.contains(port.port),
                                    isSelecting: isSelecting,
                                    isSelected: selectedPorts.contains(port.port),
                                    label: store.effectiveLabel(for: port.port),
                                    healthStatus: store.healthStatuses[port.port],
                                    onKill: { store.kill(port) },
                                    onKillTree: { store.killTree(port) },
                                    onTogglePin: { store.togglePin(port.port) },
                                    onToggleSelect: { toggleSelection(port.port) },
                                    onRestart: { store.restart(port) },
                                    onIgnore: { store.ignoreProcessName(port.processName) },
                                    onSetLabel: { store.setLabel($0, for: port.port) }
                                )
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 420)
                }
            }

            if isSelecting && !selectedPorts.isEmpty {
                HStack {
                    Button(role: .destructive, action: killSelected) {
                        Text("Kill \(selectedPorts.count) selected")
                    }
                    Spacer()
                    Button("Cancel") { exitSelectionMode() }
                }
                .padding(8)
            } else {
                HStack {
                    Button("Refresh") { store.refresh() }
                    Button(action: { isSelecting.toggle() }) {
                        Image(systemName: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .help(isSelecting ? "Cancel selection" : "Select multiple ports")
                    Spacer()
                    Picker("Theme", selection: $themeRawValue) {
                        ForEach(AppTheme.allCases) { option in
                            Image(systemName: option.iconName).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 90)
                    .labelsHidden()
                    Button(action: { isHistoryPresented.toggle() }) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .help("Port history")
                    .popover(isPresented: $isHistoryPresented) {
                        HistoryView(history: store.history)
                    }
                    Button(action: { isSettingsPresented.toggle() }) {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                    .popover(isPresented: $isSettingsPresented) {
                        SettingsView(store: store, onHotkeyChange: onHotkeyChange)
                    }
                    Spacer()
                    Button("Quit Portly") { NSApplication.shared.terminate(nil) }
                }
                .padding(8)
            }
        }
        .frame(width: 400)
        .preferredColorScheme(theme.colorScheme)
    }

    private func toggleSelection(_ port: Int) {
        if selectedPorts.contains(port) {
            selectedPorts.remove(port)
        } else {
            selectedPorts.insert(port)
        }
    }

    private func killSelected() {
        // Kill from the full port list, not the filtered view -- the button's count
        // includes every selected row, even ones a later search has hidden.
        let toKill = store.ports.filter { selectedPorts.contains($0.port) }
        store.kill(toKill)
        exitSelectionMode()
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedPorts.removeAll()
    }

    private func updateBanner(_ update: UpdateChecker.UpdateInfo) -> some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill")
            Text(updateBannerText(update))
            Spacer()
            switch store.updatePhase {
            case .idle, .failed:
                Button(update.dmgURL != nil ? "Download & Install" : "View") {
                    store.installUpdate()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            case .downloading, .installing:
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.15))
    }

    private func updateBannerText(_ update: UpdateChecker.UpdateInfo) -> String {
        switch store.updatePhase {
        case .idle:
            return "Update available: v\(update.version)"
        case .downloading:
            return "Downloading v\(update.version)…"
        case .installing:
            return "Installing v\(update.version)…"
        case .failed(let message):
            return "Update failed: \(message)"
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search ports, projects, frameworks…", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct PortRow: View {
    let info: PortInfo
    let isPinned: Bool
    let isSelecting: Bool
    let isSelected: Bool
    let label: String?
    let healthStatus: Int?
    let onKill: () -> Void
    let onKillTree: () -> Void
    let onTogglePin: () -> Void
    let onToggleSelect: () -> Void
    let onRestart: () -> Void
    let onIgnore: () -> Void
    let onSetLabel: (String) -> Void

    @State private var isEditingLabel = false
    @State private var labelText = ""

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
                    if let healthStatus {
                        Text(verbatim: "\(healthStatus)")
                            .font(.system(.caption2, design: .monospaced).bold())
                            .foregroundStyle(healthColor(for: healthStatus))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(healthColor(for: healthStatus).opacity(0.15))
                            .clipShape(Capsule())
                            .help("HTTP status from probing localhost:\(info.port)")
                    }
                    if info.isDockerManaged {
                        Image(systemName: "shippingbox.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .help("Container-mapped port (Docker)")
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
                        HStack {
                            TextField("Label", text: $labelText, onCommit: commitLabel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                            Button("Save", action: commitLabel)
                        }
                        .padding(10)
                    }
                }
                if let label {
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
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
                    }
                }
            }
            Spacer()
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .foregroundStyle(isPinned ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(isPinned ? "Unpin" : "Pin to top")
            Button(action: { TerminalRevealer.reveal(pid: info.pid) }) {
                Image(systemName: "terminal")
            }
            .buttonStyle(.borderless)
            .help("Reveal owning terminal")
            if info.commandLine != nil {
                Button(action: onRestart) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Restart (kill + relaunch same command)")
            }
            if info.proto.contains("TCP") {
                Button(action: openInBrowser) {
                    Image(systemName: "safari")
                }
                .buttonStyle(.borderless)
                .help("Open localhost:\(info.port) in browser")
            }
            Button(role: .destructive, action: onKill) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting { onToggleSelect() }
        }
        .contextMenu {
            Button("Copy localhost URL") { copyLocalhostURL() }
            if info.proto.contains("TCP") {
                Button("Copy as curl") { copyToPasteboard(CurlCommandBuilder.command(port: info.port)) }
            }
            if !info.ancestry.isEmpty {
                Button("Kill process tree (\(ProcessTreeResolver.describe(leafName: info.processName, ancestry: info.ancestry)))",
                       role: .destructive, action: onKillTree)
            }
            Button("Ignore \(info.processName)", action: onIgnore)
        }
    }

    private func beginEditingLabel() {
        labelText = label ?? ""
        isEditingLabel = true
    }

    private func commitLabel() {
        onSetLabel(labelText)
        isEditingLabel = false
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

    private func healthColor(for statusCode: Int) -> Color {
        switch HealthChecker.Category.classify(statusCode: statusCode) {
        case .healthy: return .green
        case .warning: return .orange
        case .failing: return .red
        }
    }
}
