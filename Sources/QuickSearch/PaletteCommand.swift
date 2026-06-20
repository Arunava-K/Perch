import Foundation

/// A runnable app action surfaced in the Quick Search palette's Commands
/// section — what turns the clipboard search into a universal command bar.
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    var keywords: [String] = []
    let perform: () -> Void

    /// Substring match over the title and keywords (empty query matches all).
    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        guard !q.isEmpty else { return true }
        if title.lowercased().contains(q) { return true }
        return keywords.contains { $0.lowercased().contains(q) }
    }
}
