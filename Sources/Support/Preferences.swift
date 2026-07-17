import Defaults
import Foundation

/// User-facing preferences, persisted via the `Defaults` library.
/// Kept intentionally small for now; grows as features land.
extension Defaults.Keys {
    /// Expand the notch automatically when the cursor enters it.
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)

    /// Seconds the cursor must dwell on the notch before it expands.
    static let minimumHoverDuration = Key<Double>("minimumHoverDuration", default: 0.0)

    /// Subtle haptic feedback on notch expand and paste.
    static let hapticFeedback = Key<Bool>("hapticFeedback", default: true)

    /// Hide the menu-bar status item. Settings stay reachable from the notch's
    /// gear button and the Toggle/Quick-Search hotkeys.
    static let hideMenuBarIcon = Key<Bool>("hideMenuBarIcon", default: false)

    // MARK: Notifications

    /// Opt-in: mirror delivered macOS notifications into the notch. Off by
    /// default — it needs Full Disk Access and reads the Notification Center DB.
    static let notificationMirroringEnabled = Key<Bool>("notificationMirroringEnabled", default: false)

    /// Bundle IDs whose notifications are never mirrored into the notch.
    static let mutedNotificationApps = Key<[String]>("mutedNotificationApps", default: [])

    /// Opt-in: while mirroring is active, turn on a macOS Focus so the notch
    /// *replaces* native banners instead of duplicating them. Driven by user
    /// Shortcuts (the only supported way to toggle Focus on macOS 15).
    static let dndPairingEnabled = Key<Bool>("dndPairingEnabled", default: false)

    /// Name of the Shortcut that turns the paired Focus ON.
    static let focusOnShortcutName = Key<String>("focusOnShortcutName", default: "")

    /// Name of the Shortcut that turns the paired Focus OFF.
    static let focusOffShortcutName = Key<String>("focusOffShortcutName", default: "")

    // MARK: Clipboard history

    /// Max number of unpinned clips to keep.
    static let historyLimit = Key<Int>("historyLimit", default: 200)

    /// Drop unpinned clips older than this many days.
    static let historyMaxAgeDays = Key<Int>("historyMaxAgeDays", default: 30)

    /// Permanently purge trashed clips after this many days.
    static let trashRetentionDays = Key<Int>("trashRetentionDays", default: 30)

    /// Skip clips marked concealed/auto-generated (e.g. passwords) entirely.
    static let skipSensitiveContent = Key<Bool>("skipSensitiveContent", default: true)

    // MARK: Paste formatting

    /// Strip rich-text formatting on every paste (paste as plain text).
    static let stripFormattingByDefault = Key<Bool>("stripFormattingByDefault", default: false)

    /// Bundle IDs of destination apps that should always receive plain text.
    static let plainTextApps = Key<[String]>("plainTextApps", default: [])

    /// Whether we've shown the Accessibility prompt at least once.
    static let didPromptAccessibility = Key<Bool>("didPromptAccessibility", default: false)

    // MARK: Calendar

    /// Opt-in: read today's events and show the agenda tab + meeting countdown.
    static let calendarEnabled = Key<Bool>("calendarEnabled", default: false)

    /// Event-calendar ids the user has hidden from the notch (empty = show all).
    static let hiddenCalendarIDs = Key<[String]>("hiddenCalendarIDs", default: [])

    /// Show a persistent countdown to the next meeting in the collapsed notch.
    /// Off by default — a one-time reminder peek fires regardless.
    static let calendarShowCountdown = Key<Bool>("calendarShowCountdown", default: false)

    // MARK: Reminders

    /// Opt-in: read reminders and show the reminders tab + collapsed count.
    static let remindersEnabled = Key<Bool>("remindersEnabled", default: false)

    /// Reminder-list ids the user has hidden from the notch (empty = show all).
    static let hiddenReminderListIDs = Key<[String]>("hiddenReminderListIDs", default: [])

    // MARK: Modules / tabs

    /// Module ids in display order (empty = registration order).
    static let moduleOrder = Key<[String]>("moduleOrder", default: [])

    /// Module ids the user has hidden.
    static let disabledModules = Key<[String]>("disabledModules", default: [])
}
