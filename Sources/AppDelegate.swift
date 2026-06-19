import Cocoa
import KeyboardShortcuts
import Defaults

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var statusBarController: StatusBarController?
    private var clipStore: ClipStore?
    private var clipboardMonitor: ClipboardMonitor?
    private var libraryController: LibraryWindowController?
    private var quickSearchController: QuickSearchWindowController?
    private var musicManager: MusicManager?
    private var mediaKeyTap: MediaKeyTap?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start the Sparkle updater (no-op until a feed + key are configured).
        _ = UpdaterController.shared

        // Clipboard engine: capture copies into a persisted, deduped history.
        let clipStore = ClipStore()
        let monitor = ClipboardMonitor(store: clipStore)
        monitor.start()
        self.clipStore = clipStore
        self.clipboardMonitor = monitor

        // Now-playing (Apple Music / Spotify) drives the idle notch.
        let musicManager = MusicManager()
        musicManager.start()
        self.musicManager = musicManager

        let notchController = NotchWindowController(store: clipStore, music: musicManager)
        notchController.show()
        self.notchController = notchController

        // Sneak-peek a freshly captured clip in the collapsed notch.
        clipStore.onCapture = { [weak notchController] item in
            notchController?.peek(item)
        }

        // HUD replacement: intercept volume keys → adjust + show our own HUD.
        let mediaKeyTap = MediaKeyTap()
        mediaKeyTap.onKey = { [weak notchController] key in
            switch key {
            case .volumeUp: VolumeController.adjust(by: 1.0 / 16)
            case .volumeDown: VolumeController.adjust(by: -1.0 / 16)
            case .mute: VolumeController.toggleMute()
            }
            let muted = VolumeController.isMuted()
            let value = VolumeController.current()
            let symbol = (muted || value == 0) ? "speaker.slash.fill"
                : value < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
            notchController?.showHUD(symbol: symbol, value: muted ? 0 : value)
        }
        mediaKeyTap.start()
        self.mediaKeyTap = mediaKeyTap

        let libraryController = LibraryWindowController(store: clipStore)
        self.libraryController = libraryController

        statusBarController = StatusBarController(
            onToggleNotch: { [weak notchController] in
                notchController?.toggle()
            },
            onOpenLibrary: { [weak libraryController] in
                libraryController?.show()
            },
            onClearHistory: { [weak clipStore] in
                clipStore?.clear()
            }
        )

        let quickSearchController = QuickSearchWindowController(store: clipStore)
        self.quickSearchController = quickSearchController

        // Global toggle hotkey (default ⌘⇧B, rebindable in Settings).
        KeyboardShortcuts.onKeyDown(for: .toggleNotch) { [weak notchController] in
            notchController?.toggle()
        }

        // Quick-search palette (default ⌃⌘V).
        KeyboardShortcuts.onKeyDown(for: .quickSearch) { [weak quickSearchController] in
            quickSearchController?.toggle()
        }

        // Numbered paste: ⌃⌘1 = newest … ⌃⌘0 = 10th most recent.
        for (index, name) in KeyboardShortcuts.Name.pasteRecent.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak clipStore] in
                guard let store = clipStore, store.items.indices.contains(index) else { return }
                PasteService.paste(store.items[index])
            }
        }

        // First run: nudge the user to grant Accessibility so paste-back works.
        if !AccessibilityPermission.isTrusted && !Defaults[.didPromptAccessibility] {
            Defaults[.didPromptAccessibility] = true
            AccessibilityPermission.prompt()
        }

        // Rebuild the notch window when the screen configuration changes
        // (display connected/disconnected, resolution change, etc.).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenConfigurationChanged() {
        notchController?.relayout()
    }
}
