import AppKit
import SwiftUI

/// Owns the Settings window. Because Mybar is an accessory app (no Dock icon),
/// we temporarily switch to `.regular` activation while the window is open so it
/// can take focus, then back to `.accessory` when it closes.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let registry: ModuleRegistry
    private let calendar: CalendarManager
    private var window: NSWindow?

    init(registry: ModuleRegistry, calendar: CalendarManager) {
        self.registry = registry
        self.calendar = calendar
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(registry: registry, calendar: calendar))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Mybar Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Return to background-agent mode once settings closes.
        NSApp.setActivationPolicy(.accessory)
    }
}
