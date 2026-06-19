import AppKit

/// A notification surfaced in the notch (mirrored from macOS Notification Center).
struct NotificationItem: Equatable {
    let appName: String
    let appBundleID: String?
    let title: String
    let subtitle: String?
    let body: String
    let date: Date

    /// Headline line: the notification title, falling back to the app name.
    var headline: String { title.isEmpty ? appName : title }

    /// Detail line: subtitle + body, whitespace-trimmed and combined.
    var detail: String {
        [subtitle, body]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
    }

    /// The source app's icon, resolved from its bundle id.
    var appIcon: NSImage? {
        guard let appBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
