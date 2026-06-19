import AppKit

/// Describes the physical (or synthesized) notch on a given screen.
struct NotchMetrics: Equatable {
    /// The screen the notch lives on.
    let screenFrame: CGRect
    /// Size of the bare notch the panel hugs when collapsed.
    let notchSize: CGSize
    /// Whether the screen has a real hardware notch. When false we synthesize
    /// a pill so the app still works on non-notched Macs and external displays.
    let hasPhysicalNotch: Bool

    /// Computes metrics for the screen that currently owns a hardware notch,
    /// falling back to the main screen with a synthesized notch.
    static func current() -> NotchMetrics {
        let notchedScreen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        let screen = notchedScreen ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen else {
            // No screens at all — return a harmless default.
            return NotchMetrics(
                screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                notchSize: CGSize(width: 180, height: 32),
                hasPhysicalNotch: false
            )
        }

        let topInset = screen.safeAreaInsets.top
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchWidth = screen.frame.width - left.width - right.width
            return NotchMetrics(
                screenFrame: screen.frame,
                notchSize: CGSize(width: notchWidth, height: topInset),
                hasPhysicalNotch: true
            )
        }

        // Synthesized notch for non-notched displays. Roughly menu-bar height.
        let menuBarHeight = NSStatusBar.system.thickness
        return NotchMetrics(
            screenFrame: screen.frame,
            notchSize: CGSize(width: 190, height: max(menuBarHeight, 24)),
            hasPhysicalNotch: false
        )
    }
}
