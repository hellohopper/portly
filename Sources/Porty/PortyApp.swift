import SwiftUI

@main
struct PortyApp: App {
    @StateObject private var store = PortStore()

    var body: some Scene {
        MenuBarExtra("Porty", systemImage: "network") {
            MenuContentView(store: store)
                .onAppear { store.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
