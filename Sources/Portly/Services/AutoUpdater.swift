import Foundation
import AppKit

/// Downloads a release DMG, mounts it, swaps the running app bundle for the one
/// inside, then relaunches. Self-replacement only runs when the app is installed
/// under /Applications (the Homebrew/manual-install path) -- a dev build running
/// from .build should never be silently overwritten, so that case just opens the
/// release page in the browser instead.
enum AutoUpdater {
    enum Phase: Equatable {
        case idle
        case downloading
        case installing
        case failed(String)
    }

    @MainActor
    static func downloadAndInstall(
        dmgURL: URL,
        releasePageURL: URL,
        onPhaseChange: @escaping (Phase) -> Void
    ) async {
        let currentBundlePath = Bundle.main.bundlePath
        guard currentBundlePath.hasPrefix("/Applications/") else {
            NSWorkspace.shared.open(releasePageURL)
            return
        }

        onPhaseChange(.downloading)
        guard let (downloadedURL, response) = try? await URLSession.shared.download(from: dmgURL),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            onPhaseChange(.failed("Download failed"))
            return
        }

        let dmgPath = FileManager.default.temporaryDirectory.appendingPathComponent("Portly-update-\(UUID().uuidString).dmg")
        do {
            try FileManager.default.moveItem(at: downloadedURL, to: dmgPath)
        } catch {
            onPhaseChange(.failed("Could not save the downloaded update"))
            return
        }
        defer { try? FileManager.default.removeItem(at: dmgPath) }

        onPhaseChange(.installing)
        let mountPoint = FileManager.default.temporaryDirectory.appendingPathComponent("PortlyUpdateMount-\(UUID().uuidString)")

        guard run("/usr/bin/hdiutil", ["attach", dmgPath.path, "-nobrowse", "-mountpoint", mountPoint.path]) else {
            onPhaseChange(.failed("Could not mount the update image"))
            return
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"]) }

        let sourceApp = mountPoint.appendingPathComponent("Portly.app")
        guard FileManager.default.fileExists(atPath: sourceApp.path) else {
            onPhaseChange(.failed("Update image did not contain Portly.app"))
            return
        }

        // replaceItemAt moves (not copies) the new item into place, and a move off the
        // read-only DMG mount fails at its delete-source step -- stage a writable copy
        // in the temp directory first.
        let stagedApp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortlyUpdateStaging-\(UUID().uuidString)")
            .appendingPathComponent("Portly.app")
        do {
            try FileManager.default.createDirectory(
                at: stagedApp.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: sourceApp, to: stagedApp)
        } catch {
            onPhaseChange(.failed("Could not stage the update (\(error.localizedDescription))"))
            return
        }
        defer { try? FileManager.default.removeItem(at: stagedApp.deletingLastPathComponent()) }

        let destinationApp = URL(fileURLWithPath: currentBundlePath)
        do {
            _ = try FileManager.default.replaceItemAt(destinationApp, withItemAt: stagedApp)
        } catch {
            onPhaseChange(.failed("Could not replace the app bundle (\(error.localizedDescription))"))
            return
        }

        relaunch(at: destinationApp)
    }

    private static func relaunch(at appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
