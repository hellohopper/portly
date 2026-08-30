import Foundation
import AppKit
import PortlyCore

enum TerminalRevealer {

    private struct KnownTerminal {
        let processName: String
        let bundleID: String
    }

    /// Terminal emulators Portly recognizes by their process name when walking a
    /// port's process ancestry. Only Terminal.app and iTerm2 expose a scripting
    /// dictionary that can select the exact tab/session by tty; the rest (Warp,
    /// Ghostty, WezTerm, Alacritty, kitty, Hyper, Rio) have no stable public API for
    /// that, so revealing one of those just brings the app to the front.
    private static let knownTerminals: [KnownTerminal] = [
        KnownTerminal(processName: "Terminal", bundleID: "com.apple.Terminal"),
        KnownTerminal(processName: "iTerm2", bundleID: "com.googlecode.iterm2"),
        KnownTerminal(processName: "Ghostty", bundleID: "com.mitchellh.ghostty"),
        KnownTerminal(processName: "WezTerm", bundleID: "com.github.wez.wezterm"),
        KnownTerminal(processName: "wezterm-gui", bundleID: "com.github.wez.wezterm"),
        KnownTerminal(processName: "Alacritty", bundleID: "org.alacritty"),
        KnownTerminal(processName: "kitty", bundleID: "net.kovidgoyal.kitty"),
        KnownTerminal(processName: "Warp", bundleID: "dev.warp.Warp-Stable"),
        KnownTerminal(processName: "Hyper", bundleID: "co.zeit.hyper"),
        KnownTerminal(processName: "Rio", bundleID: "com.raphaelamorim.rio")
    ]

    /// Best-effort: brings the owning terminal to the front and, for Terminal.app or
    /// iTerm2, selects the tab/session whose tty matches the given process. Falls
    /// back to just activating Terminal.app if no terminal ancestor is found at all
    /// (e.g. the process was spawned by an IDE).
    static func reveal(pid: Int32) {
        guard let tty = resolveTTY(pid: pid) else {
            activateTerminal()
            return
        }

        guard let terminal = resolveTerminalApp(pid: pid) else {
            activateTerminal()
            return
        }

        switch terminal.processName {
        case "Terminal":
            revealInTerminalApp(tty: tty)
        case "iTerm2":
            revealInITerm(tty: tty)
        default:
            activate(bundleID: terminal.bundleID)
        }
    }

    private static func revealInTerminalApp(tty: String) {
        let script = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "/dev/\(tty)" then
                        set selected tab of w to t
                        set index of w to 1
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        runAppleScript(script, fallback: activateTerminal)
    }

    private static func revealInITerm(tty: String) {
        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "/dev/\(tty)" then
                            select t
                            select s
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        runAppleScript(script, fallback: { activate(bundleID: "com.googlecode.iterm2") })
    }

    private static func runAppleScript(_ source: String, fallback: () -> Void) {
        guard let appleScript = NSAppleScript(source: source) else {
            fallback()
            return
        }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if error != nil {
            fallback()
        }
    }

    private static func activateTerminal() {
        activate(bundleID: "com.apple.Terminal")
    }

    private static func activate(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func resolveTTY(pid: Int32) -> String? {
        guard let output = Shell.run("/bin/ps", ["-o", "tty=", "-p", "\(pid)"]) else { return nil }

        let tty = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return (tty.isEmpty || tty == "??") ? nil : tty
    }

    /// Walks the process ancestry (unlike `ProcessTreeResolver.ancestry`, this climbs
    /// *past* shells on purpose -- it's looking for the terminal emulator itself,
    /// which is exactly the kind of process that resolver treats as a boundary).
    private static func resolveTerminalApp(pid: Int32) -> KnownTerminal? {
        let table = ProcessTreeResolver.snapshot()
        var current = pid
        var visited: Set<Int32> = [pid]

        for _ in 0..<24 {
            guard let node = table[current], node.ppid > 1, !visited.contains(node.ppid) else { return nil }
            guard let parent = table[node.ppid] else { return nil }
            if let match = knownTerminals.first(where: { $0.processName == parent.name }) {
                return match
            }
            visited.insert(node.ppid)
            current = node.ppid
        }
        return nil
    }
}
