import PortlyCore
import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: PortStore
    let onHotkeyChange: (UInt32, UInt32) -> Void

    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var hotkeyKeyCode = HotkeyManager.storedKeyCode
    @State private var hotkeyModifiers = HotkeyManager.storedModifiers
    @State private var newIgnoreText = ""
    @State private var suggestedFreePort: Int?
    @State private var exportedConfigMessage: String?
    /// Resolved when the panel appears rather than inside `body`: building it walks the
    /// filesystem looking for git roots, and `body` re-runs on every 2s port refresh.
    @State private var exportable: [PortStore.ExportableProject] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.headline)

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    LaunchAtLoginManager.setEnabled(newValue)
                }

            HStack {
                Text("Toggle shortcut")
                Spacer()
                HotkeyRecorderView(currentKeyCode: hotkeyKeyCode, currentModifiers: hotkeyModifiers) { keyCode, modifiers in
                    hotkeyKeyCode = keyCode
                    hotkeyModifiers = modifiers
                    HotkeyManager.save(keyCode: keyCode, modifiers: modifiers)
                    onHotkeyChange(keyCode, modifiers)
                }
            }

            Divider()

            Toggle("Enable .localhost proxy", isOn: $store.isLocalhostProxyEnabled)
            if let proxyStartupError = store.proxyStartupError {
                Text(proxyStartupError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Give any port a name.localhost:\(LocalhostProxyServer.port) address from the globe icon on its row.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("Free port")
                Spacer()
                if let suggestedFreePort {
                    Text(verbatim: "\(suggestedFreePort)")
                        .font(.system(.body, design: .monospaced).bold())
                }
                Button("Suggest") { suggestedFreePort = store.suggestFreePort() }
            }
            Text("Picks an unused port from the common 3000/5000/8000 dev ranges.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Show pinned port health in menu bar", isOn: $store.showsPinnedStatusInMenuBar)
            Text("Adds a small status glyph next to the icon: ● healthy, ◐ slow, ▲ 4xx, ■ 5xx.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Show total CPU/MEM in menu bar", isOn: $store.showsResourceSummaryInMenuBar)
            Text("Adds the combined CPU and memory usage across every tracked port next to the icon.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Alert on idle ports", isOn: $store.isIdlePortAlertsEnabled)
            Text("Notifies when a port has seen no network activity for 30 minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.isIdlePortAlertsEnabled {
                Toggle("Also kill idle ports automatically", isOn: $store.isIdlePortAutoKillEnabled)
                if store.isIdlePortAutoKillEnabled {
                    Text("This will SIGTERM a port's process after 30 minutes of no network activity, with no further confirmation.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            Text("Export .portly.json")
                .font(.subheadline.bold())
            if exportable.isEmpty {
                Text("No manually labeled ports from a git project to export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(exportable) { project in
                    HStack {
                        Text(project.name)
                            .font(.caption)
                        Spacer()
                        Button("Export") {
                            if let url = store.exportProjectConfig(project) {
                                exportedConfigMessage = "Saved \(url.path)"
                            } else {
                                exportedConfigMessage = "Couldn't write \(project.name)/.portly.json"
                            }
                        }
                    }
                }
                if let exportedConfigMessage {
                    Text(exportedConfigMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("Ignored processes")
                .font(.subheadline.bold())

            if store.ignoredProcessNames.isEmpty {
                Text("None — right-click a port and choose \"Ignore\" to hide it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.ignoredProcessNames.sorted(), id: \.self) { name in
                    HStack {
                        Text(name)
                            .font(.caption)
                        Spacer()
                        Button(action: { store.unignoreProcessName(name) }) {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Divider()

            HStack {
                Text("Export current list")
                Spacer()
                Button("JSON") { export(.json) }
                Button("CSV") { export(.csv) }
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { exportable = store.exportableProjects() }
    }

    private func export(_ format: PortExporter.Format) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "portly-export.\(format.fileExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = PortExporter.export(store.ports, format: format)
        try? data.write(to: url)
    }
}
