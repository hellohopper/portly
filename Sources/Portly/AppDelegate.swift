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
