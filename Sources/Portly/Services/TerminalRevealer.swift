import Foundation
import AppKit
import PortlyCore

enum TerminalRevealer {

    /// Best-effort: brings Terminal.app to the front and selects the tab whose tty
    /// matches the given process, falling back to just activating Terminal.app if
    /// the process isn't attached to a Terminal.app tty (e.g. spawned by an IDE,
    /// or running in a different terminal emulator).
    static func reveal(pid: Int32) {
        guard let tty = resolveTTY(pid: pid) else {
            activateTerminal()
            return
        }

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

        guard let appleScript = NSAppleScript(source: script) else {
            activateTerminal()
            return
        }

        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if error != nil {
            activateTerminal()
        }
    }

    private static func activateTerminal() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func resolveTTY(pid: Int32) -> String? {
        guard let output = Shell.run("/bin/ps", ["-o", "tty=", "-p", "\(pid)"]) else { return nil }

        let tty = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return (tty.isEmpty || tty == "??") ? nil : tty
    }
}
