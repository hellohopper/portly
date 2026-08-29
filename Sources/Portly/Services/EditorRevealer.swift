import Foundation
import AppKit

/// Opens a port's project directory in whichever code editor is installed, found
/// via LaunchServices rather than PATH lookups (a menu bar app launched from
/// Finder often has a PATH too minimal to find `code`/`cursor` shims).
enum EditorRevealer {
    private static let bundleIdentifiers = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "dev.zed.Zed",
        "com.sublimetext.4",
        "com.sublimetext.3",
    ]

    /// Resolved once. This is consulted from every row's `body`, and each miss costs
    /// up to six LaunchServices lookups -- re-running that per row per render made
    /// scrolling the list do real work for an answer that never changes.
    static let isInstalled: Bool = resolvedApplication() != nil

    static func open(workingDirectory: String) {
        guard let appURL = resolvedApplication() else { return }
        let directoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        NSWorkspace.shared.open([directoryURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func resolvedApplication() -> URL? {
        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }
        return nil
    }
}
