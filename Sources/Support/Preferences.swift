import Defaults
import Foundation

/// User-facing preferences, persisted via the `Defaults` library.
/// Kept intentionally small for now; grows as features land.
extension Defaults.Keys {
    /// Expand the notch automatically when the cursor enters it.
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)

    /// Seconds the cursor must dwell on the notch before it expands.
    static let minimumHoverDuration = Key<Double>("minimumHoverDuration", default: 0.0)

    // MARK: Clipboard history

    /// Max number of unpinned clips to keep.
    static let historyLimit = Key<Int>("historyLimit", default: 200)

    /// Drop unpinned clips older than this many days.
    static let historyMaxAgeDays = Key<Int>("historyMaxAgeDays", default: 30)

    /// Skip clips marked concealed/auto-generated (e.g. passwords) entirely.
    static let skipSensitiveContent = Key<Bool>("skipSensitiveContent", default: true)

    /// Whether we've shown the Accessibility prompt at least once.
    static let didPromptAccessibility = Key<Bool>("didPromptAccessibility", default: false)
}
