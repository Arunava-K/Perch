import AppKit

/// Adds a menu-bar status item so the accessory app is discoverable and
/// quittable, and exposes Settings.
@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let onToggleNotch: () -> Void
    private let onOpenLibrary: () -> Void
    private let onClearHistory: () -> Void

    init(
        onToggleNotch: @escaping () -> Void,
        onOpenLibrary: @escaping () -> Void,
        onClearHistory: @escaping () -> Void
    ) {
        self.onToggleNotch = onToggleNotch
        self.onOpenLibrary = onOpenLibrary
        self.onClearHistory = onClearHistory
        setup()
    }

    private func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "Mybar"
        )

        let menu = NSMenu()
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
            withTitle: "About Mybar",
            action: #selector(about),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Quit Mybar",
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self

        item.menu = menu
        statusItem = item
    }

    @objc private func toggleNotch() {
        onToggleNotch()
    }

    @objc private func openLibrary() {
        onOpenLibrary()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
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
