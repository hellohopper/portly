import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hotkeyManager: HotkeyManager?
    private let store = PortStore()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Portly")
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 400, height: 480)
        popover.contentViewController = NSHostingController(rootView: MenuContentView(store: store, onHotkeyChange: { [weak self] keyCode, modifiers in
            self?.hotkeyManager?.reregister(keyCode: keyCode, modifiers: modifiers)
        }))
        self.popover = popover

        store.start()
        store.checkForUpdate()
        NotificationManager.requestAuthorization()

        store.$hasAlert
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasAlert in
                self?.statusItem?.button?.contentTintColor = hasAlert ? .systemRed : nil
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
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.clearAlert()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
