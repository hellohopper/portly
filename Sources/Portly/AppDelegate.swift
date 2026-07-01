import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hotkeyManager: HotkeyManager?
    private let store = PortStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Portly")
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 400, height: 480)
        popover.contentViewController = NSHostingController(rootView: MenuContentView(store: store))
        self.popover = popover

        store.start()
        store.checkForUpdate()
        NotificationManager.requestAuthorization()

        hotkeyManager = HotkeyManager { [weak self] in
            self?.togglePopover()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
