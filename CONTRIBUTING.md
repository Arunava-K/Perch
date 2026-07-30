# Contributing to Perch

Thanks for helping. Perch is a free, open-source macOS notch utility (clipboard-first).

## Requirements

- macOS 15+
- Xcode 16+ (CI uses Xcode on macOS 26 runners)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build & run

```sh
xcodegen generate
xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Debug \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Debug/Perch.app
```

Stop a CLI-launched instance: `pkill -x Perch`.

`project.yml` is the source of truth. `Perch.xcodeproj` and `Sources/Info.plist` are generated — do not hand-edit them.

See `AGENTS.md` for architecture constraints (notch panel, SQLite migrations, permissions).

## Pull requests

1. Keep changes focused; match existing Swift style (no drive-by refactors).
2. Prefer modules via `NotchModule` + `ModuleRegistry` for new notch surfaces.
3. Schema changes need a **new** GRDB migration — never edit an applied migration.
4. Do not commit secrets, signing identities, or local `build/` artifacts.
5. Update `README.md` / `ROADMAP.md` when user-facing behavior changes.

## License

By contributing, you agree your contributions are licensed under the MIT License (see `LICENSE`).
