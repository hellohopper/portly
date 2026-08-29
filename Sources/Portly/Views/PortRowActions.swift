import PortlyCore
import SwiftUI
import AppKit

/// The trailing button cluster on a port row: six actions with independent
/// visibility rules, split out so the row itself stays readable.
struct PortRowActions: View {
    let info: PortInfo
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onRestart: () -> Void
    let onKill: () -> Void
    let onOpenInBrowser: () -> Void

    var body: some View {
        Button(action: onTogglePin) {
            Image(systemName: isPinned ? "star.fill" : "star")
                .foregroundStyle(isPinned ? .yellow : .secondary)
        }
        .buttonStyle(.borderless)
        .help(isPinned ? "Unpin" : "Pin to top")

        Button(action: { TerminalRevealer.reveal(pid: info.pid) }) {
            Image(systemName: "terminal")
        }
        .buttonStyle(.borderless)
        .help("Reveal owning terminal")

        if let workingDirectory = info.workingDirectory, EditorRevealer.isInstalled {
            Button(action: { EditorRevealer.open(workingDirectory: workingDirectory) }) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(.borderless)
            .help("Open project in editor")
        }

        if info.commandLine != nil {
            Button(action: onRestart) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Restart (kill + relaunch same command)")
        }

        if info.isTCP {
            Button(action: onOpenInBrowser) {
                Image(systemName: "safari")
            }
            .buttonStyle(.borderless)
            .help("Open localhost:\(info.port) in browser")
        }

        Button(role: .destructive, action: onKill) {
            Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.borderless)
    }
}
