import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // The hosting window effectively never changes; re-dispatching on every
        // SwiftUI update just to re-assign the same value is pure churn.
        guard window !== nsView.window else { return }
        DispatchQueue.main.async { window = nsView.window }
    }
}
