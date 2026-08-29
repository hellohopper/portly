import PortlyCore
import Foundation
import AppKit

/// Owns the check-for-update / download / install cycle, split out of PortStore --
/// it shares nothing with port scanning beyond living in the same menu.
@MainActor
final class UpdateCoordinator: ObservableObject {
    @Published private(set) var availableUpdate: UpdateChecker.UpdateInfo?
    @Published private(set) var phase: AutoUpdater.Phase = .idle

    func checkForUpdate() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        Task {
            availableUpdate = await UpdateChecker.checkForUpdate(currentVersion: currentVersion)
        }
    }

    func install() {
        guard let update = availableUpdate else { return }
        // No DMG asset on the release: the best we can do is send them to the page.
        guard let dmgURL = update.dmgURL else {
            NSWorkspace.shared.open(update.url)
            return
        }
        Task {
            await AutoUpdater.downloadAndInstall(dmgURL: dmgURL, releasePageURL: update.url) { [weak self] phase in
                self?.phase = phase
            }
        }
    }
}
