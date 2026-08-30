import Foundation
import AppKit
import CryptoKit

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
        sha256URL: URL?,
        releasePageURL: URL,
        onPhaseChange: @escaping (Phase) -> Void
    ) async {
        let currentBundlePath = Bundle.main.bundlePath
        guard currentBundlePath.hasPrefix("/Applications/") else {
            NSWorkspace.shared.open(releasePageURL)
            return
        }

        onPhaseChange(.downloading)

        // Fetch the expected checksum before downloading the (much larger) DMG,
        // so a broken/missing sha256 asset fails fast rather than after the download.
        var expectedSHA256: String?
        if let sha256URL {
            guard let checksum = await fetchExpectedChecksum(from: sha256URL) else {
                onPhaseChange(.failed("Could not verify the update's checksum"))
                return
            }
            expectedSHA256 = checksum
        }

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

        if let expectedSHA256 {
            guard let actualSHA256 = sha256(ofFileAt: dmgPath), actualSHA256 == expectedSHA256 else {
                onPhaseChange(.failed("Downloaded update failed checksum verification"))
                return
            }
        }

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

    /// Parses a `shasum -a 256` style file ("<hex>  Portly.dmg") and returns the hex digest.
    private static func fetchExpectedChecksum(from url: URL) async -> String? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let hex = text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
        guard let hex, hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex.lowercased()
    }

    private static func sha256(ofFileAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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
