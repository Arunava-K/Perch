import Foundation
import GRDB
import AppKit
import Defaults

/// Mirrors macOS notifications into the notch by polling the Notification Center
/// database (group.com.apple.usernoted). Requires Full Disk Access. The DB schema
/// is private/undocumented, so everything here is defensive.
@MainActor
final class NotificationMonitor {
    /// Called for each newly delivered notification.
    var onNotification: ((NotificationItem) -> Void)?
    /// Called once if the DB can't be opened (almost always missing Full Disk Access).
    var onNeedsFullDiskAccess: (() -> Void)?

    private var lastRecID: Int64 = 0
    private var connected = false
    private var pollTimer: Timer?
    private var retryTimer: Timer?
    private var askedForAccess = false
    private var observation: Defaults.Observation?
    private let ownBundleID = Bundle.main.bundleIdentifier

    var isConnected: Bool { connected }

    /// Observe the opt-in pref and run the mirror only while it's enabled.
    /// Fires immediately with the current value, so this both reflects the
    /// saved choice at launch and reacts to live toggles from Settings.
    func activate() {
        observation = Defaults.observe(.notificationMirroringEnabled) { [weak self] change in
            if change.newValue { self?.start() } else { self?.stop() }
        }
    }

    /// Tear down polling/retry. Safe to call when not running.
    func stop() {
        pollTimer?.invalidate(); pollTimer = nil
        retryTimer?.invalidate(); retryTimer = nil
        connected = false
        askedForAccess = false
    }

    /// A fresh read-only connection. We deliberately open one per read: a single
    /// long-lived read-only connection to the system's live WAL database gets
    /// stuck on a stale snapshot and stops seeing new notifications.
    private func makeConnection() -> DatabaseQueue? {
        guard let path = Self.dbPath else { return nil }
        var config = Configuration()
        config.readonly = true
        return try? DatabaseQueue(path: path, configuration: config)
    }

    /// Candidate DB locations across macOS versions.
    private static var dbPath: String? {
        let base = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted"
        for sub in ["db2/db", "db/db"] {
            let path = base + "/" + sub
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    func start() {
        guard pollTimer == nil, retryTimer == nil else { return }  // already running
        if openDatabase() {
            beginPolling()
        } else {
            if !askedForAccess { askedForAccess = true; onNeedsFullDiskAccess?() }
            scheduleRetry()
        }
    }

    // MARK: Connection

    /// Probe connectivity (verifies Full Disk Access + schema) and seed lastRecID
    /// to the current max so we don't replay history.
    @discardableResult
    private func openDatabase() -> Bool {
        guard let queue = makeConnection() else { return false }
        do {
            let maxID = try queue.read { db in
                try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(rec_id), 0) FROM record") ?? 0
            }
            connected = true
            lastRecID = maxID  // start fresh; don't replay history
            return true
        } catch {
            return false  // almost always missing Full Disk Access
        }
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                if self.openDatabase() {
                    t.invalidate()
                    self.retryTimer = nil
                    self.beginPolling()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    // MARK: Polling

    private func beginPolling() {
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        guard let queue = makeConnection() else { return }  // fresh snapshot each poll

        // If Notification Center cleared its table, rec_ids reset below our
        // tracker — resync so we don't go blind to every new notification.
        let currentMax = (try? queue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(rec_id), 0) FROM record") ?? 0
        }) ?? 0
        if currentMax < lastRecID { lastRecID = currentMax }

        let rows = (try? queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT record.rec_id AS rec_id, record.data AS data, app.identifier AS identifier
                FROM record JOIN app ON record.app_id = app.app_id
                WHERE record.rec_id > ?
                ORDER BY record.rec_id ASC
                """, arguments: [lastRecID])
        }) ?? []

        // Read the mute list once per poll; resolved at delivery time so edits
        // in Settings take effect on the next notification.
        let muted = Set(Defaults[.mutedNotificationApps])

        for row in rows {
            let recID: Int64 = row["rec_id"] ?? 0
            lastRecID = max(lastRecID, recID)
            let bundleID: String? = row["identifier"]
            if let bundleID, bundleID == ownBundleID { continue }
            if let bundleID, muted.contains(bundleID) { continue }
            guard let data: Data = row["data"] else { continue }
            if let item = Self.parse(data: data, bundleID: bundleID) {
                onNotification?(item)
            }
        }
    }

    // MARK: Parsing

    private static func parse(data: Data, bundleID: String?) -> NotificationItem? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }

        // The payload nests the request under "req" on most macOS versions.
        let req = (plist["req"] as? [String: Any]) ?? plist
        let title = (req["titl"] as? String) ?? ""
        let subtitle = req["subt"] as? String
        let body = (req["body"] as? String) ?? ""
        guard !title.isEmpty || !body.isEmpty else { return nil }

        let appName = bundleID.flatMap(appDisplayName(for:)) ?? "Notification"
        return NotificationItem(
            appName: appName,
            appBundleID: bundleID,
            title: title,
            subtitle: subtitle,
            body: body,
            date: Date()
        )
    }

    private static func appDisplayName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
