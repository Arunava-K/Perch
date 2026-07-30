# Perch

**Free, open-source macOS notch utility** — clipboard history, shelf, and live activities that live in the MacBook notch.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black.svg)](#requirements)

Perch expands from the hardware notch on hover (or hotkey). It’s clipboard-first — think [Maccy](https://github.com/p0deje/Maccy) depth with a [Boring Notch](https://github.com/TheBoredTeam/boring.notch)–style shell — not a music toy with a weak pasteboard.

## Features

| Area | What you get |
|------|----------------|
| **Clipboard** | History strip in the notch, paste-back, pin, drag in/out, OCR on images, on-device semantic search |
| **Library** | Full history window, keyword + semantic search, filters, Quick Look, trash |
| **Vault** | Lock clips with Touch ID (AES-GCM); image blobs sealed on disk |
| **Quick Search** | ⌃⌘V palette — keyword or semantic, commands, paste / plain paste |
| **Shelf** | Drag files onto the notch to stage; Share / Zip / AirDrop |
| **Live activities** | Copy peek, music flank, timer, calendar countdown, system load, volume HUD |
| **Modules** | Timer/Pomodoro, Calendar + Reminders, Music, System monitor, Weather badge, Webcam mirror |

## Install

### Release DMG (GitHub)

1. Download `Perch.dmg` from [Releases](https://github.com/Arunava-K/Perch/releases).
2. Drag **Perch** to Applications.
3. First launch (unsigned build):

```sh
xattr -dr com.apple.quarantine /Applications/Perch.app
```

Then open Perch normally.

### Homebrew (tap)

```sh
brew tap Arunava-K/perch
brew install --cask perch
```

> The tap formula lives in this repo under [`Homebrew/Casks/perch.rb`](Homebrew/Casks/perch.rb) for reference. Point a personal tap at it or copy the cask after each release (see `RELEASING.md`).

### Build from source

```sh
brew install xcodegen
git clone https://github.com/Arunava-K/Perch.git
cd Perch
xcodegen generate
xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Debug \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Debug/Perch.app
```

## Requirements

- macOS 15 Sequoia or later  
- Notched MacBook preferred (synthetic notch on other displays)  
- **Accessibility** for paste-back and media-key HUD  
- Optional: Automation (Music/Spotify), Calendar, Reminders, Location (weather), Camera, Full Disk Access (notification mirror)

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧B (default) | Toggle notch |
| ⌃⌘V | Quick Search palette |
| ⌃⌘1…0 | Paste Nth recent clip |

Rebind in **Settings → Shortcuts**.

## Permissions (progressive)

1. **First useful path:** Accessibility → paste into the frontmost app.  
2. Everything else is opt-in in Settings (Calendar, Reminders, notifications, camera, etc.).

Perch is **not sandboxed** on purpose (clipboard polling, Accessibility paste, security-scoped files).

## Project layout

- `Sources/` — app code (`Notch/`, `Clipboard/`, `Modules/`, …)  
- `project.yml` — XcodeGen project definition  
- `AGENTS.md` — engineering constraints for contributors / agents  
- `ROADMAP.md` — product direction  
- `CONTRIBUTING.md` — how to build and PR  

## License

[MIT](LICENSE)

## Acknowledgments

Inspired by patterns from [Boring Notch](https://github.com/TheBoredTeam/boring.notch), [Maccy](https://github.com/p0deje/Maccy), and [Supaste](https://www.supaste.com/).
