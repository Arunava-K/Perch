import AppKit
import SwiftUI

/// Owns the Library window. Like Settings, it flips the app to `.regular` while
/// open so the window can take focus, then back to `.accessory` on close.
@MainActor
final class LibraryWindowController: NSObject, NSWindowDelegate {
    private let store: ClipStore
    private var window: NSWindow?

    init(store: ClipStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let root = LibraryView(store: store, onCopyAndClose: { [weak self] in
                self?.window?.close()
            })
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "Clipboard History"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 520))
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
        NSApp.setActivationPolicy(.accessory)
    }
}
