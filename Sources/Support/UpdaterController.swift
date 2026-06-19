import AppKit
import Sparkle

/// Thin wrapper around Sparkle's standard updater. Auto-update only starts once a
/// public key + feed are configured (see RELEASING.md); until then it stays
/// dormant so it can't error on launch.
@MainActor
final class UpdaterController {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController?

    private init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        if key.isEmpty {
            controller = nil
        } else {
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }
    }

    var isConfigured: Bool { controller != nil }

    func checkForUpdates() {
        guard let controller else {
            let alert = NSAlert()
            alert.messageText = "Updates not configured"
            alert.informativeText = "This build has no update feed yet. See RELEASING.md to set one up."
            alert.runModal()
            return
        }
        controller.checkForUpdates(nil)
    }
}
