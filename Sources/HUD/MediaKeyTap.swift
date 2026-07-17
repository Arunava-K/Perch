import AppKit

/// Intercepts the hardware volume keys via a CGEvent tap so Perch can show its
/// own HUD instead of the system one. Requires Accessibility / Input Monitoring;
/// if that's not granted, `start()` fails gracefully and the system HUD stays.
final class MediaKeyTap {
    enum Key { case volumeUp, volumeDown, mute, brightnessUp, brightnessDown }

    var onKey: ((Key) -> Void)?

    /// When false, brightness keys pass through untouched (so the system HUD
    /// still works on machines where we can't set brightness ourselves).
    var handlesBrightness = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    // NX system-defined event type and media-key codes.
    private static let nxSystemDefined: CGEventType = CGEventType(rawValue: 14)!
    private static let soundUp = 0
    private static let soundDown = 1
    private static let brightnessUp = 2
    private static let brightnessDown = 3
    private static let mute = 7

    /// Start the tap, and if it can't be created yet (permission not granted),
    /// keep retrying so granting Accessibility while running takes effect without
    /// a relaunch. Returns true if the tap started immediately.
    @discardableResult
    func startWithRetry() -> Bool {
        if start() { return true }
        guard retryTimer == nil else { return false }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.start() {
                t.invalidate()
                self.retryTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
        return false
    }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }  // already running
        let mask = CGEventMask(1 << 14)  // NX_SYSDEFINED
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            let this = Unmanaged<MediaKeyTap>.fromOpaque(userInfo!).takeUnretainedValue()
            return this.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("MediaKeyTap: tap not created (Accessibility/Input Monitoring needed)")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable if the system disabled the tap.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0x0000_FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A

        let key: Key?
        switch keyCode {
        case Self.soundUp: key = .volumeUp
        case Self.soundDown: key = .volumeDown
        case Self.mute: key = .mute
        case Self.brightnessUp where handlesBrightness: key = .brightnessUp
        case Self.brightnessDown where handlesBrightness: key = .brightnessDown
        default: key = nil
        }

        guard let key else { return Unmanaged.passUnretained(event) }
        if isKeyDown { onKey?(key) }
        return nil  // consume both down & up so the system HUD never shows
    }
}
