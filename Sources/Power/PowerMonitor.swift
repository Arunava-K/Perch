import Foundation
import IOKit.ps

/// Watches the power source and Low Power Mode, surfacing transitions as notch
/// live activities: plugging in / unplugging, Low Power Mode on/off, and a
/// one-shot low-battery warning. All public API — no private frameworks.
@MainActor
final class PowerMonitor {
    /// Emits (SF Symbol, message) for the collapsed-notch activity.
    var onActivity: ((_ symbol: String, _ text: String) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var lastPluggedIn: Bool?
    private var lastLowPower: Bool?
    private var lowBatteryNotified = false

    func start() {
        // Power-source changes (plug/unplug, capacity).
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.powerSourceChanged() }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        // Low Power Mode changes.
        NotificationCenter.default.addObserver(
            self, selector: #selector(lowPowerChanged),
            name: .NSProcessInfoPowerStateDidChange, object: nil
        )

        // Seed current state silently so we only announce real transitions.
        lastPluggedIn = snapshot().pluggedIn
        lastLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
    }

    @objc private func lowPowerChanged() {
        let on = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard on != lastLowPower else { return }
        lastLowPower = on
        onActivity?(on ? "bolt.badge.a.fill" : "bolt.badge.a",
                    on ? "Low Power On" : "Low Power Off")
    }

    private func powerSourceChanged() {
        let state = snapshot()

        if state.pluggedIn != lastPluggedIn {
            lastPluggedIn = state.pluggedIn
            if state.pluggedIn {
                onActivity?("bolt.fill", "Charging")
            } else {
                onActivity?("battery.100", "On Battery")
            }
        }

        // One-shot low-battery warning while on battery; re-arms once charged up.
        if !state.pluggedIn, state.level <= 0.2, !lowBatteryNotified {
            lowBatteryNotified = true
            onActivity?("battery.25", "Low Battery · \(Int(state.level * 100))%")
        } else if state.pluggedIn || state.level > 0.25 {
            lowBatteryNotified = false
        }
    }

    private func snapshot() -> (pluggedIn: Bool, level: Double, charging: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return (true, 1, false)  // desktop / no battery → treat as plugged in
        }

        let plugged = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
        let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
        let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
        let level = max > 0 ? Double(current) / Double(max) : 1
        return (plugged, level, charging)
    }
}
