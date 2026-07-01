import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: PortStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.ports.isEmpty {
                Text("No listening ports")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(store.ports) { port in
                    PortRow(info: port, onKill: { store.kill(port) })
                    Divider()
                }
            }

            HStack {
                Button("Refresh") { store.refresh() }
                Spacer()
                Button("Quit Porty") { NSApplication.shared.terminate(nil) }
            }
            .padding(8)
        }
        .frame(width: 320)
    }
}

private struct PortRow: View {
    let info: PortInfo
    let onKill: () -> Void

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
                HStack(spacing: 4) {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let cpuPercent = info.cpuPercent {
                        Circle()
                            .fill(energyColor(for: cpuPercent))
                            .frame(width: 6, height: 6)
                            .help("Energy impact (based on CPU usage)")
                    }
                }
            }
            Spacer()
            if info.proto == "TCP" {
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

    private var subtitle: String {
        var parts = ["\(info.processName)", "pid \(info.pid)", info.proto]
        if let uptimeSeconds = info.uptimeSeconds {
            parts.append(UptimeResolver.format(uptimeSeconds))
        }
        if let cpuPercent = info.cpuPercent, let memPercent = info.memPercent {
            parts.append(String(format: "CPU %.0f%% · MEM %.0f%%", cpuPercent, memPercent))
        }
        return parts.joined(separator: " · ")
    }

    private func energyColor(for cpuPercent: Double) -> Color {
        switch ProcessMetricsResolver.EnergyLevel.from(cpuPercent: cpuPercent) {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
}
