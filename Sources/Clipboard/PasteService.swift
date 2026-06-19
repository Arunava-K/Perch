import AppKit
import Defaults

/// Decides whether a paste should strip rich-text formatting, based on the
/// global default and per-destination-app rules.
enum FormatRules {
    static func shouldStripFormatting(forBundleID id: String?) -> Bool {
        if Defaults[.stripFormattingByDefault] { return true }
        if let id, Defaults[.plainTextApps].contains(id) { return true }
        return false
    }
}

/// Pastes a clip into the frontmost app: copies it, then (if Accessibility is
/// granted) simulates ⌘V. Falls back to copy-only when not trusted.
@MainActor
enum PasteService {
    enum Outcome { case pasted, copiedOnly }

    /// - Parameter forcePlain: overrides the format rules when non-nil (e.g. an
    ///   explicit "Paste as Plain Text" action).
    @discardableResult
    static func paste(_ item: ClipItem, forcePlain: Bool? = nil) -> Outcome {
        let destination = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let plain = forcePlain ?? FormatRules.shouldStripFormatting(forBundleID: destination)
        ClipboardWriter.copy(item, asPlainText: plain)

        guard AccessibilityPermission.isTrusted else {
            AccessibilityPermission.prompt()
            return .copiedOnly
        }

        // Give the frontmost app a beat to observe the new pasteboard, then ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sendPasteKeystroke()
        }
        return .pasted
    }

    private static func sendPasteKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9  // "v"

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
