import AppKit
import SwiftUI
import Combine
import PortlyCore
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hotkeyManager: HotkeyManager?
    private let store = PortStore()
    private let updates = UpdateCoordinator()
    private var cancellables: Set<AnyCancellable> = []
    private var notificationHandler: NotificationActionHandler?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Portly")
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        // A transient popover mostly closes by clicking elsewhere, which never goes
        // through togglePopover -- the delegate is the only reliable close signal.
        popover.delegate = self
        popover.contentSize = NSSize(width: 400, height: 480)
        popover.contentViewController = NSHostingController(rootView: MenuContentView(store: store, updates: updates, onHotkeyChange: { [weak self] keyCode, modifiers in
            self?.hotkeyManager?.reregister(keyCode: keyCode, modifiers: modifiers)
        }))
        self.popover = popover

        store.start()
        updates.checkForUpdate()
        let handler = NotificationActionHandler { [weak self] action in
            self?.store.perform(action)
        }
        UNUserNotificationCenter.current().delegate = handler
        notificationHandler = handler
        NotificationManager.requestAuthorization()

        store.$hasAlert
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasAlert in
                self?.statusItem?.button?.contentTintColor = hasAlert ? .systemRed : nil
            }
            .store(in: &cancellables)

        // "Is my API still green" shouldn't require opening the panel. Debounced:
        // a tint that changes every couple of seconds is noise, not information.
        Publishers.CombineLatest(store.$healthResults, store.$showsPinnedStatusInMenuBar)
            .debounce(for: .seconds(3), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateMenuBarStatus()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(store.$ports, store.$showsResourceSummaryInMenuBar)
            .debounce(for: .seconds(3), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateMenuBarStatus()
            }
            .store(in: &cancellables)

        hotkeyManager = HotkeyManager { [weak self] in
            self?.togglePopover()
        }

        // Docs tooling: renders the menu view to /tmp/portly-snapshot.png on request
        // (used to regenerate the README/website screenshot without screen recording
        // permissions). Trigger:
        //   osascript -e 'use framework "Foundation"' \
        //     -e 'current application'"'"'s NSDistributedNotificationCenter'"'"'s defaultCenter()'"'"'s postNotificationName:"dev.hellohopper.portly.render-snapshot" object:(missing value) userInfo:(missing value) deliverImmediately:true'
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("dev.hellohopper.portly.render-snapshot"),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.renderSnapshot()
            }
        }
    }

    private func updateMenuBarStatus() {
        guard let button = statusItem?.button else { return }

        var parts: [String] = []
        if store.showsPinnedStatusInMenuBar, let summary = store.pinnedHealthSummary {
            parts.append(Self.statusGlyph(for: summary))
        }
        if store.showsResourceSummaryInMenuBar, let resources = store.resourceSummary {
            parts.append(String(format: "%.0f%% %.0f%%", resources.cpuPercent, resources.memPercent))
        }
        button.title = parts.isEmpty ? "" : " " + parts.joined(separator: " ")
    }

    private static func statusGlyph(for category: HealthChecker.Category) -> String {
        switch category {
        case .healthy: return "●"
        case .slow: return "◐"
        case .warning: return "▲"
        case .failing: return "■"
        }
    }

    /// Opens the popover and writes its CGWindow number to /tmp/portly-window-id so
    /// external tooling can `screencapture -l<id>` a pixel-perfect screenshot, then
    /// closes the popover again a few seconds later.
    private func renderSnapshot() {
        if popover?.isShown != true {
            togglePopover()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let window = self?.popover?.contentViewController?.view.window else { return }
            try? "\(window.windowNumber)".write(
                toFile: "/tmp/portly-window-id", atomically: true, encoding: .utf8
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                self?.popover?.performClose(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        TunnelManager.shared.stopAll()
    }

    // MARK: - portly:// links

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = PortlyURLCommand.parse(url) else { continue }
            handle(command)
        }
    }

    private func handle(_ command: PortlyURLCommand) {
        if case .show = command {
            store.perform(command)
            showPopover()
            return
        }
        if command.isDestructive && !store.trustsURLSchemeActions && !confirm(command) {
            return
        }
        if !store.perform(command), let port = command.port {
            NSSound.beep()
            NSLog("Portly: portly:// link for port \(port) ignored -- nothing is listening there")
        }
    }

    /// Any web page can try to open a portly:// link; a kill or restart through one
    /// has to be confirmed by the user unless they turned that off in Settings.
    private func confirm(_ command: PortlyURLCommand) -> Bool {
        guard let port = command.port else { return false }
        let holder = store.ports.first { $0.port == port }
        let verb: String
        switch command {
        case .restart: verb = "Restart"
        case .forceKill: verb = "Force kill"
        default: verb = "Kill"
        }
        let alert = NSAlert()
        alert.messageText = "\(verb) port \(port)?"
        alert.informativeText = holder.map { "A portly:// link asked to \(verb.lowercased()) \($0.processName) (pid \($0.pid))." }
            ?? "A portly:// link asked to \(verb.lowercased()) whatever is listening on port \(port)."
        alert.addButton(withTitle: verb)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showPopover() {
        guard let popover, !popover.isShown else {
            store.requestSearchFocus()
            return
        }
        togglePopover()
    }

    func popoverDidClose(_ notification: Notification) {
        store.setPanelVisible(false)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil) // popoverDidClose drops the poll rate
        } else {
            store.clearAlert()
            store.setPanelVisible(true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            store.requestSearchFocus()
        }
    }
}
