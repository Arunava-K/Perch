import AppKit
import Defaults

/// Thin wrapper over the trackpad haptic engine. No-ops when the user has
/// disabled haptics or on hardware without a Force Touch trackpad.
enum Haptics {
    /// A light tap — used for notch expand and paste confirmation.
    static func tap() {
        guard Defaults[.hapticFeedback] else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}
