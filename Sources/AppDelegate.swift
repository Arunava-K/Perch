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
    private var powerMonitor: PowerMonitor?
    private var notificationMonitor: NotificationMonitor?
    private var focusPairing: FocusPairingController?
    private var shelfStore: ShelfStore?
    private var timerEngine: TimerEngine?
    private var calendarManager: CalendarManager?
    private var reminderManager: ReminderManager?
    private var weatherManager: WeatherManager?
    private var cameraManager: CameraManager?
    private var moduleRegistry: ModuleRegistry?
    private var settingsController: SettingsWindowController?

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

        // Shelf: a staging tray for dragged-in files/items.
        let shelfStore = ShelfStore()
        self.shelfStore = shelfStore

        // Timer / Pomodoro: drives the Timer tab + the collapsed live countdown.
        let timerEngine = TimerEngine()
        self.timerEngine = timerEngine

        // Calendar / Up Next: today's agenda tab + collapsed meeting countdown.
        // Opt-in — only reads events once the user enables it in Settings.
        let calendarManager = CalendarManager()
        self.calendarManager = calendarManager

        // Reminders: incomplete items grouped by urgency. Opt-in — only reads
        // reminders once the user enables it in Settings.
        let reminderManager = ReminderManager()
        self.reminderManager = reminderManager

        // Webcam mirror (top-right corner of the notch). Camera runs only while
        // the mirror is visible.
        let cameraManager = CameraManager()
        self.cameraManager = cameraManager

        // Weather badge: current conditions from Open-Meteo (free, no key).
        let weatherManager = WeatherManager()
        self.weatherManager = weatherManager

        // Register the notch modules (tab order = registration order).
        let registry = ModuleRegistry(modules: [
            ClipboardModule(store: clipStore),
            ShelfModule(shelf: shelfStore),
            TimerModule(timer: timerEngine),
            CalendarModule(calendar: calendarManager, reminders: reminderManager),
            MusicModule(music: musicManager),
        ])
        self.moduleRegistry = registry

        let notchController = NotchWindowController(registry: registry, music: musicManager, timer: timerEngine, calendar: calendarManager, weather: weatherManager, camera: cameraManager)
        notchController.show()
        self.notchController = notchController

        // Sneak-peek a freshly captured clip in the collapsed notch.
        clipStore.onCapture = { [weak notchController] item in
            notchController?.peek(item)
        }

        // HUD replacement: intercept volume + brightness keys → adjust + show
        // our own HUD. Brightness is only intercepted when we can actually set it.
        let mediaKeyTap = MediaKeyTap()
        mediaKeyTap.handlesBrightness = BrightnessController.shared.isAvailable
        mediaKeyTap.onKey = { [weak notchController] key in
            switch key {
            case .volumeUp, .volumeDown, .mute:
                // AppleScript volume I/O can stall; keep the event-tap path free.
                Task.detached {
                    switch key {
                    case .volumeUp: VolumeController.adjust(by: 1.0 / 16)
                    case .volumeDown: VolumeController.adjust(by: -1.0 / 16)
                    case .mute: VolumeController.toggleMute()
                    default: break
                    }
                    let muted = VolumeController.isMuted()
                    let value = VolumeController.current()
                    let symbol = (muted || value == 0) ? "speaker.slash.fill"
                        : value < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
                    await MainActor.run {
                        notchController?.showHUD(symbol: symbol, value: muted ? 0 : value)
                    }
                }

            case .brightnessUp, .brightnessDown:
                let delta = (key == .brightnessUp ? 1.0 : -1.0) / 16
                let value = BrightnessController.shared.adjust(by: delta)
                notchController?.showHUD(symbol: "sun.max.fill", value: value)
            }
        }
        mediaKeyTap.startWithRetry()
        self.mediaKeyTap = mediaKeyTap

        // Power live activities: charging, Low Power Mode, low battery.
        let powerMonitor = PowerMonitor()
        powerMonitor.onActivity = { [weak notchController] symbol, text in
            notchController?.showMessage(symbol: symbol, text: text)
        }
        powerMonitor.start()
        self.powerMonitor = powerMonitor

        // Mirror macOS notifications into the notch (opt-in; needs Full Disk
        // Access). activate() runs the mirror only while the pref is enabled and
        // reacts to live toggles from Settings.
        let notificationMonitor = NotificationMonitor()
        notificationMonitor.onNotification = { [weak notchController] item in
            notchController?.showNotification(item)
        }
        notificationMonitor.onNeedsFullDiskAccess = { [weak notchController] in
            notchController?.showMessage(symbol: "lock.shield", text: "Grant Full Disk Access")
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
        notificationMonitor.activate()
        self.notificationMonitor = notificationMonitor

        // Optional Focus pairing: while mirroring is on, turn on a user Focus so
        // the notch replaces native banners instead of duplicating them.
        let focusPairing = FocusPairingController()
        focusPairing.activate()
        self.focusPairing = focusPairing

        let libraryController = LibraryWindowController(store: clipStore)
        self.libraryController = libraryController

        // Start reading events / reminders only if the user opted in previously.
        calendarManager.startIfEnabled()
        reminderManager.startIfEnabled()

        // Weather auto-starts (passive badge, no opt-in needed).
        weatherManager.start()

        let settingsController = SettingsWindowController(registry: registry, calendar: calendarManager, reminders: reminderManager)
        self.settingsController = settingsController

        // The notch's gear button opens Settings (also reachable when the menu
        // bar icon is hidden).
        notchController.onOpenSettings = { [weak settingsController] in
            settingsController?.show()
        }

        statusBarController = StatusBarController(
            onToggleNotch: { [weak notchController] in
                notchController?.toggle()
            },
            onOpenLibrary: { [weak libraryController] in
                libraryController?.show()
            },
            onOpenSettings: { [weak settingsController] in
                settingsController?.show()
            },
            onClearHistory: { [weak clipStore] in
                clipStore?.clear()
            }
        )

        // App commands surfaced in the Quick Search palette's Commands section.
        let paletteCommands: [PaletteCommand] = [
            PaletteCommand(id: "toggle-notch", title: "Toggle Notch",
                           subtitle: "Open or close the notch panel.",
                           icon: "rectangle.topthird.inset.filled",
                           keywords: ["notch", "show", "hide", "panel"]) { [weak notchController] in
                notchController?.toggle()
            },
            PaletteCommand(id: "clipboard-history", title: "Open Clipboard History",
                           subtitle: "Browse the full clipboard library.",
                           icon: "clock.arrow.circlepath",
                           keywords: ["history", "library", "clips"]) { [weak libraryController] in
                libraryController?.show()
            },
            PaletteCommand(id: "open-settings", title: "Open Settings",
                           subtitle: "Adjust Perch's preferences.",
                           icon: "gearshape",
                           keywords: ["settings", "preferences", "config"]) { [weak settingsController] in
                settingsController?.show()
            },
            PaletteCommand(id: "start-focus", title: "Start Focus Session",
                           subtitle: "Begin a Pomodoro focus timer.",
                           icon: "timer",
                           keywords: ["timer", "focus", "pomodoro", "start"]) { [weak timerEngine] in
                timerEngine?.startPomodoro()
            },
            PaletteCommand(id: "start-timer-5", title: "Start 5-Minute Timer",
                           subtitle: "Begin a quick 5-minute countdown.",
                           icon: "timer",
                           keywords: ["timer", "5", "quick", "countdown"]) { [weak timerEngine] in
                timerEngine?.startCustom(minutes: 5)
            },
            PaletteCommand(id: "stop-timer", title: "Stop Timer",
                           subtitle: "Cancel the running timer.",
                           icon: "stop.circle",
                           keywords: ["timer", "stop", "cancel"]) { [weak timerEngine] in
                timerEngine?.stop()
            },
            PaletteCommand(id: "clear-history", title: "Clear Clipboard History",
                           subtitle: "Trash all unpinned clips.",
                           icon: "trash",
                           keywords: ["clear", "delete", "history", "empty"]) { [weak clipStore] in
                clipStore?.clear()
            },
            PaletteCommand(id: "check-updates", title: "Check for Updates",
                           subtitle: "See if a newer Perch is available.",
                           icon: "arrow.down.circle",
                           keywords: ["update", "upgrade", "version"]) {
                UpdaterController.shared.checkForUpdates()
            },
        ]

        let quickSearchController = QuickSearchWindowController(store: clipStore, commands: paletteCommands)
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

    func applicationWillTerminate(_ notification: Notification) {
        // Don't leave the user stuck in the paired Focus after Perch quits.
        focusPairing?.deactivateForQuit()
    }
}
