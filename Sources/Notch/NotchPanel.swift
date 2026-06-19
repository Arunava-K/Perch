import AppKit
import SwiftUI

/// A borderless, non-activating panel that floats above the menu bar so it can
/// render in and around the hardware notch.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Sit just above the menu bar so we can render in/around the notch and
        // over fullscreen apps.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        isMovable = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
    }

    // Keep the panel from stealing focus from the user's active app.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts the SwiftUI content and makes the window click-through everywhere
/// except the currently interactive notch rect.
final class NotchContainerView: NSView {
    /// Supplies the interactive rect in this view's (window) coordinates.
    var interactiveRectProvider: () -> CGRect = { .zero }

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRectProvider().contains(point) else { return nil }
        return super.hitTest(point)
    }

    // Act on the first click even though the panel never becomes key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// `NSHostingView` defaults `acceptsFirstMouse` to false, so a click on a button
/// inside a non-activating panel is swallowed (it tries to key the window
/// instead of triggering). Returning true makes clips clickable on first click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
