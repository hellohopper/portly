import SwiftUI
import AppKit

/// A button that, when clicked, listens for the next key combo the user presses
/// (must include at least one modifier) and reports it back as Carbon key code + modifiers.
struct HotkeyRecorderView: View {
    let currentKeyCode: UInt32
    let currentModifiers: UInt32
    let onChange: (UInt32, UInt32) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            Text(isRecording ? "Press a key combo…" : KeyComboFormatter.string(keyCode: currentKeyCode, modifiers: currentModifiers))
                .frame(minWidth: 100)
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let combo = KeyComboFormatter.carbonCombo(from: event) {
                onChange(combo.keyCode, combo.modifiers)
                stopRecording()
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
