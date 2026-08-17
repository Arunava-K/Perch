# Agent Instructions

## Project Shape

- This is a single macOS Swift/SwiftUI accessory app; `Sources/main.swift` sets the activation policy to `.accessory`, and `Sources/AppDelegate.swift` wires the monitors, persistence, modules, notch window, settings, and global shortcuts.
- `Sources/Modules/NotchModule.swift` and `ModuleRegistry` are the extension boundary for notch tabs. New feature surfaces should be implemented as a module and registered in `AppDelegate`, not added as unrelated branches throughout the UI.
- The notch uses a non-activating `NSPanel`; hover is intentionally driven by cursor polling in `NotchWindowController`, not SwiftUI `.onHover` or event monitors.

## Build And Verify

- `project.yml` is the source of truth. `Perch.xcodeproj` and `Sources/Info.plist` are generated and ignored; run `xcodegen generate` after changing the project definition or package configuration.
- Local command-line verification:
  ```sh
  xcodegen generate
  xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Debug \
    -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
  open build/Build/Products/Debug/Perch.app
  ```
- The repository has no test target, lint task, formatter task, CI workflow, or pre-commit hook. Treat a successful Xcode build plus focused manual verification as the available check.
- The app has no normal window or Dock icon; inspect the notch/menu-bar item after launching. Stop a command-line-launched instance with `pkill -x Perch`.

## Data And Runtime Constraints

- Clip data currently lives in SQLite at `~/Library/Application Support/Perch/perch.sqlite`, managed through GRDB migrations in `Sources/Database/AppDatabase.swift` and repository operations in `ClipRepository.swift`. `clips.json`/`shelf.json` are legacy inputs imported once, not the active store.
- Schema changes must be added as a new ordered `DatabaseMigrator` migration. Do not edit an existing migration that may already have run for users.
- Image payloads are content-addressed PNG sidecars under `~/Library/Application Support/Perch/blobs`; preserve repository reference cleanup when changing clip deletion or storage behavior.
- Paste-back and media-key interception require Accessibility/Input Monitoring permissions. Apple Music/Spotify integration requires Automation permission; notification mirroring requires Full Disk Access; Calendar and camera features are opt-in and permission-gated. These paths cannot be fully exercised headlessly.
- This is deliberately non-sandboxed direct distribution because clipboard polling, Accessibility paste-back, and security-scoped file access depend on it.

## Release

- Releases are **unsigned DMG** distributed via GitHub Actions (no Developer ID or Sparkle needed).
- Workflow: tag `v*` → push → `.github/workflows/release.yml` builds universal binary, packages `Perch.dmg`, publishes release.
- Users bypass Gatekeeper with `xattr -dr com.apple.quarantine /Applications/Perch.app`.
- `scripts/release.sh` builds locally with `CODE_SIGNING_ALLOWED=NO` and packages `.dmg`.
- `project.yml`: hardened runtime off for Release, CODE_SIGN_STYLE Manual, CODE_SIGN_IDENTITY "Perch Dev", sparkle stubs dormant.
- SPM package versions are pinned with `exactVersion` in `project.yml`. If `Defaults` >= 9.0.7 starts requiring Swift tools 6.2, pin to 9.0.6 until the CI runner's Xcode catches up.

## System Monitor Module

- `SystemMonitorManager` polls per-core CPU (P/E split via Mach host_processor_info + sysctl perflevel), memory breakdown (wired/active/compressed/inactive/free via vm_statistics64), GPU (AGXAccelerator IOKit), swap (vm.swapusage), thermal state (ProcessInfo), disk, battery every 2s.
- Per-core usage = busyΔ / totalΔ **per core** (not divided by sum of all cores). Top processes via `proc_listpids` + `PROC_PIDTASKINFO` deltas.
- `SystemMonitorTab` is four Control Center–style tiles (CPU, Memory, Disk, GPU): large value, quiet detail line, hairline progress. Soft white at rest; yellow/red only under load. No battery row.
- CPU detail shows P/E %; GPU detail shows thermal state (Cool/Warm/Hot).
- Load badge / module indicator / collapsed flank use `Defaults[.systemMonitorBadgeMetric]` (max / cpu / memory).
- Collapsed idle flank when load ≥ threshold and timer/calendar/media inactive (`CollapsedSystemLoadView`).
- Settings → System: collapsed activity, threshold, badge metric, tile visibility.
- `SystemMonitorModule` sets `hiddenFromTabBar: true`; ear layout: WeatherBadge → webcam → SystemLoadBadge → settings.

## Dictation

- WhisperFlow-style STT, fully local via whisper.cpp. Not a module — `DictationManager` owns the flow; the collapsed-notch flank (`CollapsedDictationView`) has top precedence among idle flanks, and hover-expansion is suppressed while it's active.
- Engine: vendored prebuilt XCFramework at `Vendor/Whisper/whisper.xcframework` (official whisper.cpp v1.9.2 macOS slice, Metal-accelerated, metallib embedded). Consumed through the local SPM package in `Vendor/Whisper/Package.swift`; bumping = re-trim from a release zip and update the comment.
- GGML models are downloaded on demand from `huggingface.co/ggerganov/whisper.cpp` into `~/Library/Application Support/Perch/models/` (`DictationModelStore`); nothing model-related is bundled. Files start with the little-endian ggml magic `6c 6d 67 67` — verify with that, not the string "ggml".
- Audio path: `AVAudioEngine` input tap → `AVAudioConverter` → 16 kHz mono Float32; samples buffered under `NSLock` (audio thread), RMS → published `level` for the waveform. `WhisperTranscriber` caches the whisper context across sessions on a private serial queue.
- Trigger: `toggleDictation` shortcut (default ⌥Space, rebindable) + Quick Search command. Toggle model: press = record, press = transcribe + paste at cursor via `PasteService.pastePlainText`; click the flank = discard. Transcripts are never stored.
- Requires microphone permission (`AVAudioApplication`) + Accessibility for auto-paste (copy-only fallback otherwise). Cannot be exercised headlessly; verify manually after building.
