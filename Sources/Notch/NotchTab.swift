import Foundation

/// Tabs shown in the expanded notch. Add a case here + a branch in
/// `NotchRootView.tabContent` to introduce a new feature surface.
enum NotchTab: String, CaseIterable, Identifiable {
    case clipboard
    case pinned
    case shelf
    case music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .pinned: return "Pinned"
        case .shelf: return "Shelf"
        case .music: return "Music"
        }
    }

    var icon: String {
        switch self {
        case .clipboard: return "doc.on.clipboard.fill"
        case .pinned: return "pin.fill"
        case .shelf: return "tray.full.fill"
        case .music: return "music.note"
        }
    }
}
