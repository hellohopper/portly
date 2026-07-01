import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: PortStore
    @AppStorage("appTheme") private var themeRawValue: String = AppTheme.system.rawValue
    @State private var searchText: String = ""

    private var theme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    private var filteredPorts: [PortInfo] {
        store.ports.filter { $0.matches(query: searchText) }
    }

    private var sections: [PortGrouping.Section] {
        PortGrouping.sections(for: filteredPorts, pinned: store.pinnedPorts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                                    onKill: { store.kill(port) },
                                    onTogglePin: { store.togglePin(port.port) }
                                )
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 420)
                }
            }

            HStack {
                Button("Refresh") { store.refresh() }
                Spacer()
                Picker("Theme", selection: $themeRawValue) {
                    ForEach(AppTheme.allCases) { option in
                        Image(systemName: option.iconName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 90)
                .labelsHidden()
                Spacer()
                Button("Quit Portly") { NSApplication.shared.terminate(nil) }
            }
            .padding(8)
        }
        .frame(width: 400)
        .preferredColorScheme(theme.colorScheme)
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
    let onKill: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        HStack {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: "\(info.port)")
                        .font(.system(.body, design: .monospaced).bold())
                    if let projectName = info.projectName {
                        Text(projectLabel(name: projectName, branch: info.gitBranch))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(verbatim: primaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        .contextMenu {
            Button("Copy localhost URL") { copyLocalhostURL() }
        }
    }

    private func openInBrowser() {
        guard let url = URL(string: "http://localhost:\(info.port)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyLocalhostURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("http://localhost:\(info.port)", forType: .string)
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
        return String(format: "CPU %.0f%% · MEM %.0f%%", cpuPercent, memPercent)
    }

    private func energyColor(for cpuPercent: Double) -> Color {
        switch ProcessMetricsResolver.EnergyLevel.from(cpuPercent: cpuPercent) {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
}
