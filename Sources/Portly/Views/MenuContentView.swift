import PortlyCore
import SwiftUI
import AppKit

struct MenuContentView: View {
    @ObservedObject var store: PortStore
    let onHotkeyChange: (UInt32, UInt32) -> Void
    @AppStorage("appTheme") private var themeRawValue: String = AppTheme.system.rawValue
    @State private var searchText: String = ""
    @State private var isSelecting: Bool = false
    /// Row identities (`PortInfo.id`, i.e. pid+port), not port numbers: two processes
    /// can listen on the same port on different local addresses, and keying these off
    /// the number alone made selecting or focusing one row act on the other.
    @State private var selectedRows: Set<String> = []
    @State private var isSettingsPresented: Bool = false
    @State private var isHistoryPresented: Bool = false
    @State private var focusedRowID: String?
    @State private var keyMonitor: Any?
    @State private var hostWindow: NSWindow?
    @FocusState private var isSearchFocused: Bool

    private var theme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    private var filteredPorts: [PortInfo] {
        // Normalise the needle once per filter pass rather than once per row.
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return store.ports }
        return store.ports.filter { matchesSearch($0, needle: needle) }
    }

    private func matchesSearch(_ info: PortInfo, needle: String) -> Bool {
        if info.matches(query: needle) { return true }
        // Labels (manual or .portly.json) live in the store keyed by port, not on
        // PortInfo, so they need their own check to be searchable.
        guard let label = store.effectiveLabel(for: info.port) else { return false }
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
                    ScrollViewReader { proxy in
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
                                        isSelected: selectedRows.contains(port.id),
                                        isFocused: focusedRowID == port.id,
                                        label: store.effectiveLabel(for: port.port),
                                        healthStatus: store.healthStatuses[port.port],
                                        onKill: { store.kill(port) },
                                        onKillTree: { store.killTree(port) },
                                        onTogglePin: { store.togglePin(port.port) },
                                        onToggleSelect: { toggleSelection(port.id) },
                                        onRestart: { store.restart(port) },
                                        onIgnore: { store.ignoreProcessName(port.processName) },
                                        onSetLabel: { store.setLabel($0, for: port.port) },
                                        proxyName: store.proxyNames[port.port],
                                        isProxyEnabled: store.isLocalhostProxyEnabled,
                                        onSetProxyName: { store.setProxyName($0, for: port.port) }
                                    )
                                    Divider()
                                }
                            }
                        }
                        .frame(maxHeight: 420)
                        .onChange(of: focusedRowID) { newValue in
                            guard let newValue else { return }
                            withAnimation { proxy.scrollTo(newValue) }
                        }
                    }
                }
            }

            if isSelecting && !selectedRows.isEmpty {
                HStack {
                    Button(role: .destructive, action: killSelected) {
                        Text("Kill \(selectedRows.count) selected")
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
        .background(WindowAccessor(window: $hostWindow))
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: store.searchFocusRequestID) { _ in isSearchFocused = true }
    }

    // MARK: - Keyboard navigation

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// Returns true when the event was consumed. Events for other windows (label
    /// editor, Settings/History popovers) are always passed through.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.window === hostWindow else { return false }

        // `sections` re-filters and re-groups the whole list; compute it once per
        // keystroke rather than once per branch.
        let visibleRows = sections.flatMap(\.ports).map(\.id)

        switch event.keyCode {
        case 125: // down arrow
            focusedRowID = KeyboardNavigator.move(from: focusedRowID, in: visibleRows, direction: .down)
            return true
        case 126: // up arrow
            focusedRowID = KeyboardNavigator.move(from: focusedRowID, in: visibleRows, direction: .up)
            return true
        case 36, 76: // return / keypad enter
            guard let focused = focusedRow(), focused.isTCP,
                  let url = URL(string: "http://localhost:\(focused.port)") else { return false }
            NSWorkspace.shared.open(url)
            return true
        case 51 where event.modifierFlags.contains(.command): // cmd-delete
            guard let focused = focusedRow() else { return false }
            store.kill(focused)
            return true
        case 53: // escape: clear the search first; a second press closes the popover
            guard !searchText.isEmpty else { return false }
            searchText = ""
            return true
        default:
            return false
        }
    }

    private func focusedRow() -> PortInfo? {
        guard let focusedRowID else { return nil }
        return filteredPorts.first { $0.id == focusedRowID }
    }

    private func toggleSelection(_ rowID: String) {
        if selectedRows.contains(rowID) {
            selectedRows.remove(rowID)
        } else {
            selectedRows.insert(rowID)
        }
    }

    private func killSelected() {
        // Kill from the full port list, not the filtered view -- the button's count
        // includes every selected row, even ones a later search has hidden.
        let toKill = store.ports.filter { selectedRows.contains($0.id) }
        store.kill(toKill)
        exitSelectionMode()
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedRows.removeAll()
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
                .focused($isSearchFocused)
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
