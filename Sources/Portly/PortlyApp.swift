import SwiftUI

@main
struct PortlyApp: App {
    @StateObject private var store = PortStore()

    var body: some Scene {
        MenuBarExtra("Portly", systemImage: "network") {
            MenuContentView(store: store)
                .onAppear { store.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
