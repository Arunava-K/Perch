# Agent Instructions

## Project Shape

- This is a single macOS Swift/SwiftUI accessory app; `Sources/main.swift` sets the activation policy to `.accessory`, and `Sources/AppDelegate.swift` wires the monitors, persistence, modules, notch window, settings, and global shortcuts.
- `Sources/Modules/NotchModule.swift` and `ModuleRegistry` are the extension boundary for notch tabs. New feature surfaces should be implemented as a module and registered in `AppDelegate`, not added as unrelated branches throughout the UI.
- The notch uses a non-activating `NSPanel`; hover is intentionally driven by cursor polling in `NotchWindowController`, not SwiftUI `.onHover` or event monitors.

## Build And Verify

- `project.yml` is the source of truth. `Mybar.xcodeproj` and `Sources/Info.plist` are generated and ignored; run `xcodegen generate` after changing the project definition or package configuration.
- Local command-line verification:
  ```sh
  xcodegen generate
  xcodebuild -project Mybar.xcodeproj -scheme Mybar -configuration Debug \
    -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
  open build/Build/Products/Debug/Mybar.app
  ```
- The repository has no test target, lint task, formatter task, CI workflow, or pre-commit hook. Treat a successful Xcode build plus focused manual verification as the available check.
- The app has no normal window or Dock icon; inspect the notch/menu-bar item after launching. Stop a command-line-launched instance with `pkill -x Mybar`.

## Data And Runtime Constraints

- Clip data currently lives in SQLite at `~/Library/Application Support/Mybar/mybar.sqlite`, managed through GRDB migrations in `Sources/Database/AppDatabase.swift` and repository operations in `ClipRepository.swift`. `clips.json`/`shelf.json` are legacy inputs imported once, not the active store.
- Schema changes must be added as a new ordered `DatabaseMigrator` migration. Do not edit an existing migration that may already have run for users.
- Image payloads are content-addressed PNG sidecars under `~/Library/Application Support/Mybar/blobs`; preserve repository reference cleanup when changing clip deletion or storage behavior.
- Paste-back and media-key interception require Accessibility/Input Monitoring permissions. Apple Music/Spotify integration requires Automation permission; notification mirroring requires Full Disk Access; Calendar and camera features are opt-in and permission-gated. These paths cannot be fully exercised headlessly.
- This is deliberately non-sandboxed direct distribution because clipboard polling, Accessibility paste-back, and security-scoped file access depend on it.

## Release

- Releases require Developer ID signing, notarization, and Sparkle credentials. Follow `RELEASING.md`; the command is `DEV_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh`.
- `scripts/release.sh` builds `generic/platform=macOS` (arm64 + x86_64), enables hardened runtime, notarizes, staples, and fails if Sparkle feed/key are still placeholders unless `ALLOW_UNCONFIGURED_SPARKLE=1`.
- Do not treat the placeholder `SUFeedURL` or empty `SUPublicEDKey` in `project.yml` as production-ready; configure them before enabling Sparkle updates.
- SPM package versions are pinned with `exactVersion` in `project.yml`.
