import AppKit

/// Intercepts the hardware volume keys via a CGEvent tap so Mybar can show its
/// own HUD instead of the system one. Requires Accessibility / Input Monitoring;
/// if that's not granted, `start()` fails gracefully and the system HUD stays.
final class MediaKeyTap {
    enum Key { case volumeUp, volumeDown, mute }

    var onKey: ((Key) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // NX system-defined event type and media-key codes.
    private static let nxSystemDefined: CGEventType = CGEventType(rawValue: 14)!
    private static let soundUp = 0
    private static let soundDown = 1
    private static let mute = 7

    @discardableResult
    func start() -> Bool {
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
        default: key = nil
        }

        guard let key else { return Unmanaged.passUnretained(event) }
        if isKeyDown { onKey?(key) }
        return nil  // consume both down & up so the system HUD never shows
    }
}
