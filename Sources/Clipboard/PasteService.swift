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
        return commitPasteboard()
    }

    /// Paste several clips at once (multi-file pasteboard — ideal for images).
    @discardableResult
    static func pasteItems(_ items: [ClipItem]) -> Outcome {
        guard !items.isEmpty else { return .copiedOnly }
        if items.count == 1 { return paste(items[0]) }
        ClipDragExporter.copyToPasteboard(items)
        return commitPasteboard()
    }

    /// Join text-like clips into one plain-text paste (double newlines).
    /// Falls back to multi-file paste when nothing is text-like.
    @discardableResult
    static func pasteCombined(_ items: [ClipItem]) -> Outcome {
        let parts = items.compactMap(\.plainTextBody)
        guard parts.count >= 2 else {
            return parts.count == 1
                ? pasteText(parts[0])
                : pasteItems(items)
        }
        return pasteText(parts.joined(separator: "\n\n"))
    }

    /// Whether Combine is useful for this selection (2+ text-like clips).
    static func canCombine(_ items: [ClipItem]) -> Bool {
        items.lazy.filter { $0.plainTextBody != nil }.count >= 2
    }

    private static func pasteText(_ string: String) -> Outcome {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        return commitPasteboard()
    }

    private static func commitPasteboard() -> Outcome {
        guard AccessibilityPermission.isTrusted else {
            AccessibilityPermission.prompt()
            return .copiedOnly
        }
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
