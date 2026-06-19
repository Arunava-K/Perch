import CoreGraphics
import Foundation

/// Reads and sets the built-in display's brightness via the private
/// DisplayServices framework (resolved at runtime so we never hard-link a
/// private symbol). If the framework or symbols aren't available, the
/// controller reports `isAvailable == false` and we leave the system HUD alone.
final class BrightnessController {
    static let shared = BrightnessController()

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getFn: GetFn?
    private let setFn: SetFn?

    let isAvailable: Bool

    init() {
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_NOW
        )
        if let handle,
           let getSym = dlsym(handle, "DisplayServicesGetBrightness"),
           let setSym = dlsym(handle, "DisplayServicesSetBrightness") {
            getFn = unsafeBitCast(getSym, to: GetFn.self)
            setFn = unsafeBitCast(setSym, to: SetFn.self)
            // Probe: only claim availability if a read actually succeeds.
            var value: Float = 0
            isAvailable = getFn?(CGMainDisplayID(), &value) == 0
        } else {
            getFn = nil
            setFn = nil
            isAvailable = false
        }
    }

    /// Current brightness 0...1.
    func current() -> Double {
        guard let getFn else { return 0 }
        var value: Float = 0
        return getFn(CGMainDisplayID(), &value) == 0 ? Double(value) : 0
    }

    /// Adjust by a delta (e.g. ±1/16 for one "bar") and return the new level.
    @discardableResult
    func adjust(by delta: Double) -> Double {
        guard let getFn, let setFn else { return 0 }
        let display = CGMainDisplayID()
        var value: Float = 0
        _ = getFn(display, &value)
        let next = Float(max(0, min(1, Double(value) + delta)))
        _ = setFn(display, next)
        return Double(next)
    }
}
