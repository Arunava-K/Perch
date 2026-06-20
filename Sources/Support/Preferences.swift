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

    // MARK: Modules / tabs

    /// Module ids in display order (empty = registration order).
    static let moduleOrder = Key<[String]>("moduleOrder", default: [])

    /// Module ids the user has hidden.
    static let disabledModules = Key<[String]>("disabledModules", default: [])
}
