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
    private let monitor: ClipboardMonitor

    private var pauseItem: NSMenuItem?
    private var ignoreNextItem: NSMenuItem?

    init(
        monitor: ClipboardMonitor,
        onToggleNotch: @escaping () -> Void,
        onOpenLibrary: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onClearHistory: @escaping () -> Void
    ) {
        self.monitor = monitor
        self.onToggleNotch = onToggleNotch
        self.onOpenLibrary = onOpenLibrary
        self.onOpenSettings = onOpenSettings
        self.onClearHistory = onClearHistory
        self.menu = NSMenu()
        buildMenu()
        observation = Defaults.observe(.hideMenuBarIcon) { [weak self] change in
            self?.applyVisibility(hidden: change.newValue)
        }
    }

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
        menu.delegate = MenuDelegate.shared
        MenuDelegate.shared.onOpen = { [weak self] in self?.refreshCaptureItems() }

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

        let pause = menu.addItem(
            withTitle: "Pause Capture",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pause.target = self
        pauseItem = pause

        let ignore = menu.addItem(
            withTitle: "Ignore Next Copy",
            action: #selector(ignoreNext),
            keyEquivalent: ""
        )
        ignore.target = self
        ignoreNextItem = ignore

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

    private func refreshCaptureItems() {
        pauseItem?.title = monitor.isPaused ? "Resume Capture" : "Pause Capture"
        ignoreNextItem?.isEnabled = !monitor.isPaused
        if monitor.ignoreNextCopy {
            ignoreNextItem?.title = "Ignore Next Copy ✓"
        } else {
            ignoreNextItem?.title = "Ignore Next Copy"
        }
    }

    @objc private func toggleNotch() { onToggleNotch() }
    @objc private func openLibrary() { onOpenLibrary() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func clearHistory() { onClearHistory() }

    @objc private func togglePause() {
        monitor.setPaused(!monitor.isPaused)
    }

    @objc private func ignoreNext() {
        monitor.ignoreNext()
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

/// Soft delegate so menu titles refresh each open without retaining the controller hard.
private final class MenuDelegate: NSObject, NSMenuDelegate {
    static let shared = MenuDelegate()
    var onOpen: (() -> Void)?
    func menuWillOpen(_ menu: NSMenu) { onOpen?() }
}
