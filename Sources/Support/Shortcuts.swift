import KeyboardShortcuts

/// Global keyboard shortcuts. Users can rebind these in Settings.
extension KeyboardShortcuts.Name {
    /// Toggle the notch open/closed from anywhere.
    static let toggleNotch = Self("toggleNotch", default: .init(.b, modifiers: [.command, .shift]))

    /// Open the quick-search palette.
    static let quickSearch = Self("quickSearch", default: .init(.v, modifiers: [.control, .command]))

    // Paste the Nth most recent clip directly (⌃⌘1 = newest … ⌃⌘0 = 10th).
    static let pasteRecent1 = Self("pasteRecent1", default: .init(.one, modifiers: [.control, .command]))
    static let pasteRecent2 = Self("pasteRecent2", default: .init(.two, modifiers: [.control, .command]))
    static let pasteRecent3 = Self("pasteRecent3", default: .init(.three, modifiers: [.control, .command]))
    static let pasteRecent4 = Self("pasteRecent4", default: .init(.four, modifiers: [.control, .command]))
    static let pasteRecent5 = Self("pasteRecent5", default: .init(.five, modifiers: [.control, .command]))
    static let pasteRecent6 = Self("pasteRecent6", default: .init(.six, modifiers: [.control, .command]))
    static let pasteRecent7 = Self("pasteRecent7", default: .init(.seven, modifiers: [.control, .command]))
    static let pasteRecent8 = Self("pasteRecent8", default: .init(.eight, modifiers: [.control, .command]))
    static let pasteRecent9 = Self("pasteRecent9", default: .init(.nine, modifiers: [.control, .command]))
    static let pasteRecent10 = Self("pasteRecent10", default: .init(.zero, modifiers: [.control, .command]))

    /// Index 0 = newest. Mapped to ⌃⌘1…⌃⌘0.
    static let pasteRecent: [KeyboardShortcuts.Name] = [
        pasteRecent1, pasteRecent2, pasteRecent3, pasteRecent4, pasteRecent5,
        pasteRecent6, pasteRecent7, pasteRecent8, pasteRecent9, pasteRecent10,
    ]
}
