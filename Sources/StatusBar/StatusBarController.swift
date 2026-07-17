import AppKit
import Defaults

/// Adds a menu-bar status item so the accessory app is discoverable and
/// quittable, and exposes Settings. The item can be hidden via Settings; the
/// notch's gear button keeps Settings reachable when it is.
@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let menu: NSMenu
    private var observation: Defaults.Observation?
    private let onToggleNotch: () -> Void
    private let onOpenLibrary: () -> Void
    private let onOpenSettings: () -> Void
    private let onClearHistory: () -> Void

    init(
        onToggleNotch: @escaping () -> Void,
        onOpenLibrary: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onClearHistory: @escaping () -> Void
    ) {
        self.onToggleNotch = onToggleNotch
        self.onOpenLibrary = onOpenLibrary
        self.onOpenSettings = onOpenSettings
        self.onClearHistory = onClearHistory
        self.menu = NSMenu()
        buildMenu()
        // Reflect the pref now and whenever it changes (live toggle from Settings).
        observation = Defaults.observe(.hideMenuBarIcon) { [weak self] change in
            self?.applyVisibility(hidden: change.newValue)
        }
    }

    /// Create or tear down the status item to match the preference.
    private func applyVisibility(hidden: Bool) {
        if hidden {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
        } else if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(
                systemSymbolName: "rectangle.topthird.inset.filled",
                accessibilityDescription: "Perch"
            )
            item.menu = menu
            statusItem = item
        }
    }

    private func buildMenu() {
        menu.addItem(
            withTitle: "Toggle Notch",
            action: #selector(toggleNotch),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Clipboard History…",
            action: #selector(openLibrary),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Clear Clipboard History",
            action: #selector(clearHistory),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "About Perch",
            action: #selector(about),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Quit Perch",
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self
    }

    @objc private func toggleNotch() {
        onToggleNotch()
    }

    @objc private func openLibrary() {
        onOpenLibrary()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func clearHistory() {
        onClearHistory()
    }

    @objc private func checkForUpdates() {
        UpdaterController.shared.checkForUpdates()
    }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
