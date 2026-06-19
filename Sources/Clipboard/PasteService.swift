import AppKit

/// Pastes a clip into the frontmost app: copies it, then (if Accessibility is
/// granted) simulates ⌘V. Falls back to copy-only when not trusted.
@MainActor
enum PasteService {
    enum Outcome { case pasted, copiedOnly }

    @discardableResult
    static func paste(_ item: ClipItem) -> Outcome {
        ClipboardWriter.copy(item)

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
