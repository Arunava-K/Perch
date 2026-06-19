import AppKit

/// Reads and sets the system output volume via AppleScript (no extra entitlements).
enum VolumeController {
    /// Current output volume, 0...1.
    static func current() -> Double {
        guard let s = runScript("output volume of (get volume settings)"),
              let v = Int(s) else { return 0 }
        return Double(v) / 100
    }

    static func isMuted() -> Bool {
        runScript("output muted of (get volume settings)") == "true"
    }

    static func setVolume(_ value: Double) {
        let clamped = max(0, min(1, value))
        _ = runScript("set volume output volume \(Int(clamped * 100))")
    }

    /// Adjust by a delta (e.g. ±1/16 for one "bar"), unmuting on increase.
    static func adjust(by delta: Double) {
        if delta > 0 && isMuted() { setMuted(false) }
        setVolume(current() + delta)
    }

    static func toggleMute() {
        setMuted(!isMuted())
    }

    static func setMuted(_ muted: Bool) {
        _ = runScript("set volume \(muted ? "with" : "without") output muted")
    }

    private static func runScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }
}
