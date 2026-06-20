import AppKit
import SwiftUI

/// A key-capable borderless panel for the quick-search palette. Remembers the
/// app that was frontmost so a pick can be pasted back into it.
private final class QuickSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class QuickSearchWindowController {
    private let store: ClipStore
    private var panel: QuickSearchPanel?
    private weak var previousApp: NSRunningApplication?

    init(store: ClipStore) {
        self.store = store
    }

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication

        if panel == nil {
            let panel = QuickSearchPanel(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
                styleMask: [.borderless],
                backing: .buffered, defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .modalPanel
            panel.isMovableByWindowBackground = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = panel
        }

        // Fresh SwiftUI tree on each open: clears the query, refocuses the field,
        // and reloads the recent list.
        let root = QuickSearchView(
            store: store,
            onPaste: { [weak self] item, forcePlain in self?.paste(item, forcePlain: forcePlain) },
            onClose: { [weak self] in self?.close() }
        )
        panel?.contentView = NSHostingView(rootView: root)

        positionCenter()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func paste(_ item: ClipItem, forcePlain: Bool) {
        close()
        // Restore the user's app, then paste into it.
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            PasteService.paste(item, forcePlain: forcePlain ? true : nil)
        }
    }

    private func positionCenter() {
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let frame = screen.frame
        let origin = CGPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2 + 80  // slightly above center
        )
        panel.setFrameOrigin(origin)
    }
}
