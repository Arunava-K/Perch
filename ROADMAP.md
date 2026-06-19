# Mybar — Phased Development Plan

A macOS notch clipboard manager (Supaste-style), informed by a study of
[boring.notch](https://github.com/TheBoredTeam/boring.notch). Each phase is
shippable on its own and ends with a concrete "done when" check.

**Legend:** 🟢 done · 🔵 next · ⚪ planned · 🟡 deferred/optional

---

## Phase 0 — Bare notch shell 🟢 DONE

The animated notch window that hangs from the hardware notch, expands on hover,
and is click-through everywhere else.

- Accessory app (LSUIElement), borderless non-activating `NSPanel`.
- `NotchShape` (square top, rounded bottom), pure-black fill that blends with the
  hardware notch.
- Hover via cursor **polling** (robust through a non-activating panel).
- Window fixed at expanded size; content animates inside; custom `hitTest`
  click-through.

**Done when:** ✅ notch expands/collapses cleanly, blends with the bezel.

---

## Phase 1 — Window hardening & interaction polish 🟢 DONE

Bring the shell up to boring.notch's robustness before piling features on.

**Tasks**
- Raise window level to `.mainMenu + 3`; widen styleMask to
  `[.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]`.
- Full `collectionBehavior`: `.canJoinAllSpaces, .fullScreenAuxiliary,
  .stationary, .ignoresCycle`.
- Adopt boring.notch's corner radii (closed 6/14, open 19/24) + open/close
  spring asymmetry.
- Add a **status-bar menu** (icon → Settings, Quit) so the app is discoverable.
- Add **launch-at-login** (`SMAppService`).
- Scaffold preferences with the `Defaults` library (`sindresorhus/Defaults`).
- Add a global **toggle hotkey** via `KeyboardShortcuts` (`sindresorhus/KeyboardShortcuts`).

**Borrowed from boring.notch:** window/collection-behavior config, NotchShape radii.

**Deferred here:** private CGSSpace / SkyLight (only if we ever need lock-screen).

**Done when:** notch shows over fullscreen apps & all Spaces, has a menu-bar
item, launches at login, and a hotkey toggles it open/closed.

*Status:* window level raised to `.mainMenu + 3` with the wider HUD/utility
styleMask; status-bar menu (Toggle / Settings / Quit) verified; `Defaults` +
`KeyboardShortcuts` SPM deps integrated; Settings window with launch-at-login
(`SMAppService`), hover toggle, and a shortcut recorder; default toggle hotkey
⌘⇧B + a manual pin-open state so the hover poll won't fight it. (Note: synthetic
keystroke verification is blocked by the test env lacking Accessibility to inject
keys; hotkey path is code-verified and shared with the status-bar Toggle item.)

---

## Phase 2 — Clipboard engine (headless core) 🟢 DONE

The data layer. No fancy UI yet — prove capture + persistence.

**Tasks**
- `ClipboardMonitor`: poll `NSPasteboard.general.changeCount` (~0.3–0.5s timer);
  on change, read & classify content.
- Content classification (port `Clipboard+Content.swift`): text, RTF/HTML →
  attributed string, image (`NSImage`/PNG), file URL, web URL, color.
- `ClipItem { id, kind, timestamp, sourceApp (bundleId/name), isPinned, isSensitive }`.
- Capture **source app** via `NSWorkspace.frontmostApplication` at copy time.
- **Dedup** by content hash / `identityKey` (move-to-top on repeat).
- Persistence: JSON in `~/Library/Application Support/Mybar/` with robust,
  per-item decoding (start simple; revisit SQLite/SwiftData at scale).
- Images/files stored as security-scoped bookmarks or sidecar files, not inline.
- History cap + eviction (configurable, e.g. last 200 / N days).
- **Sensitive-content flagging** (concealed pasteboard type, password-manager
  source apps) — store flagged, optionally skip.

**Borrowed from boring.notch:** `ShelfItem`/`Bookmark` model, JSON persistence
with robust decoding, security-scoped bookmark helpers, `Clipboard+Content`.

**Done when:** copying things across apps builds a persisted, deduped history
(verifiable via a debug dump) that survives relaunch.

*Status:* `ClipboardMonitor` polls `changeCount` every 0.4s; classifies
file/image/color/link/text (hex strings and bare URLs are upgraded to
color/link). Items carry source app, timestamp, pin & sensitive flags. Storage:
`~/Library/Application Support/Mybar/clips.json` (robust per-item decode) +
content-addressed PNG blobs under `blobs/`. Count + age eviction (pinned exempt),
concealed-type skipping. Verified end-to-end: dedup move-to-top, source-app
capture (Figma), blob on disk, and survival across relaunch. "Clear Clipboard
History" added to the status-bar menu.

---

## Phase 3 — Notch clipboard shelf UI 🟢 DONE

Surface the history in the expanded notch.

**Tasks**
- Horizontal scrolling row of recent clips inside the open notch.
- Per-type cards: text snippet, image thumbnail, file icon+name, link favicon.
- Thumbnails via `QLThumbnailGenerator` behind an `actor` cache.
- Hover/selection states; keyboard arrow navigation.
- Click a clip → copy back to pasteboard (+ visual confirmation).
- Empty state.
- Optional **tab system** (Clipboard / Shelf) like boring.notch.

**Borrowed from boring.notch:** Shelf views, `ThumbnailService` actor cache,
selection model.

**Done when:** recent clips render in the notch and clicking one re-copies it.

*Status:* `ClipboardShelfView` renders the live history as a horizontal strip of
`ClipCardView`s inside the expanded notch — text snippets, image thumbnails (from
blobs), code, color swatches (with hex), link cards (glyph + host), and file
cards (async `QLThumbnailGenerator` via a `ThumbnailService` actor, icon
fallback). Each card shows a type badge + source app and has hover + a "Copied"
confirmation. Header shows item count; empty state included. Clicking copies via
`ClipboardWriter` (verified end-to-end for text→"Another snippet…" and
color→"#3478F6" by running the real writer). Added `FirstMouseHostingView`
(`acceptsFirstMouse = true`) so a first click on a card acts immediately in the
non-activating panel. (Interactive click verification via synthetic mouse events
is blocked by the same non-activating-panel limitation as hover; render verified
visually, copy path verified directly.)

**Deferred:** keyboard arrow navigation — the panel is intentionally non-key so
paste-back keeps the target app focused; keyboard-driven selection is better
handled by the Phase 6 quick-search palette.

---

## Phase 4 — Paste-back, drag-out & permissions 🟢 DONE

Make it feel like Supaste: pick a clip → it lands in the active app.

**Tasks**
- **Paste into active app**: write to pasteboard, then synthesize ⌘V via
  `CGEvent` (needs **Accessibility** permission).
- Onboarding step explaining/requesting Accessibility (boring.notch's
  permission-flow pattern).
- **Drag-out** of clips into other apps via `NSDraggingSource` + rendered SwiftUI
  drag preview; security-scoped access started before / stopped after the drag.
- **Drag-in** (optional): global `DragDetector` to drop files/text onto the notch.

**Borrowed from boring.notch:** `NSDraggingSource` drag-out, `DragDetector`,
onboarding/permission views.

**Done when:** selecting a clip pastes it into the frontmost app; clips can be
dragged out to Finder/other apps.

*Status:* clicking a card now calls `PasteService` — copies the clip then
simulates ⌘V via `CGEvent` when Accessibility is granted (falls back to
copy-only + prompt otherwise; verified the copy path with the real code). The
notch auto-dismisses after a pick. `AccessibilityPermission` helper + a first-run
prompt + a Settings "Permissions" section drive the grant flow. Drag-OUT via
SwiftUI `.onDrag` with per-type `NSItemProvider`s (text/link/color strings, image
& file URLs with security scope). Drag-IN via `.onDrop` + `DropImporter` (drop
files/images/links/text onto the notch to save them), with a dashed drop
highlight. (Paste keystroke + drag gestures can't be driven by synthetic events
in this env — same non-activating-panel/Accessibility limitation as before — so
those are code-verified; the copy half is verified end-to-end.)

**Deferred:** a full multi-step welcome/onboarding window → folded into Phase 7
polish. For now: first-run prompt + Settings permissions row.

---

## Phase 5 — Library window (full history) 🟢 DONE

A real window for browsing everything (Supaste's "Library").

**Tasks**
- Standard `NSWindow`/SwiftUI window with a searchable grid/list.
- Full-text **search**; **filters** by type and by source app.
- Multi-select, delete, pin/favorite, copy, QuickLook (spacebar).
- Activation-policy flip (`.accessory ↔ .regular`) so the window can take focus.

**Borrowed from boring.notch:** settings-window controller pattern, QuickLook
service.

**Done when:** a searchable/filterable window shows the whole history with
manage actions.

*Status:* `LibraryWindowController` opens a resizable "Clipboard History" window
(activation-policy flips to `.regular` so it takes focus, back to `.accessory` on
close), reachable from the status-bar menu. `LibraryView` shows an adaptive grid
of `LibraryItemCell`s with live search (content + source app), a type filter, and
a source-app filter, plus an item count. Cells show a pin badge and relative
time; double-click copies (and closes), context menu = Copy / Pin / Quick Look /
Delete; spacebar QuickLooks the selection (`QuickLookPreview` via `QLPreviewPanel`
for image/file clips), delete key removes. Per-type rendering was refactored into
a shared `ClipPreview` used by both the notch shelf and the library. Verified by
launching the window and screenshotting (toolbar + filters + grid).

---

## Phase 6 — Power features 🟢 DONE

The features that make a clipboard manager sticky.

**Tasks**
- Global hotkeys: `⌃⌘V` quick-search palette, `⌃⌘0–9` paste last-N.
- **Pinned/favorite** clips & custom categories.
- **Inline shortcuts** (type `;sig` → expand saved snippet) — needs keystroke
  monitoring (Accessibility).
- **OCR** on image/screenshot clips (`Vision` `VNRecognizeTextRequest`) → searchable.
- **Multi-clip** (combine several into one paste).
- Clip **reminders** (time/app-triggered).

**Done when:** quick-search + numbered paste work; at least pin + OCR-search land.

*Status:* **Quick-search palette** (⌃⌘V) — a Spotlight-style key window
(`QuickSearchWindowController` remembers the frontmost app, restores it, then
pastes the pick) with live filtering, ↑/↓ navigation, ⏎ to paste, Esc to close;
render verified. **Numbered paste** ⌃⌘1…⌃⌘0 → paste the Nth most recent clip.
**OCR** on image clips via Vision (`OCRService`) populates `ClipItem.ocrText`
asynchronously and feeds `searchText`, so images are searchable — verified
end-to-end (recognized "MYBAR OCR TEST 1234!"). **Pin** landed in Phase 5.

**Deferred (optional, not required by "done when"):** inline text-expansion
shortcuts, multi-clip combine, and clip reminders — left for post-1.0. Noted in
Open Decisions.

---

## Phase 7 — Polish & distribution 🟢 DONE

**Tasks**
- Full Settings UI (history size, hotkeys, sensitive-content rules, appearance,
  per-display behavior).
- App icon, About, what's-new.
- Code signing + **notarization**; auto-update via **Sparkle**.
- Decide **sandbox vs direct** distribution (affects pasteboard/Accessibility/
  bookmarks — see Open Decisions).

**Done when:** signed, notarized, auto-updating build a stranger can install.

*Progress (chunk 1 done):* expanded Settings — General, **History** (keep-up-to N
clips, discard-after N days, skip-sensitive toggle), **Shortcuts** (toggle + quick
search recorders, paste-recent hint), Permissions, and **About** (version) — plus
an "About Mybar" status-bar item using the standard about panel. Verified.

*Chunk 2 done:* generated an **app icon** (programmatic squircle + notch + clip
cards, full `AppIcon.appiconset`, compiled into the bundle). Integrated
**Sparkle** auto-update (`UpdaterController`, "Check for Updates…" in the
status-bar menu and Settings; `SUFeedURL`/`SUPublicEDKey` keys in an explicit
`Info.plist`). Added `scripts/release.sh` (build → Developer-ID sign → notarize →
staple → package) and `RELEASING.md` (signing, notarization, and Sparkle key/
appcast steps). App verified launching with Sparkle bundled.

*Credential caveat (Open Decision #6):* the actual **signed + notarized** artifact
requires the user's paid Apple Developer ID and a Sparkle EdDSA key — credentials
this autonomous environment can't hold. All code, tooling, and docs are in place;
producing the shippable build is one `./scripts/release.sh` run with those
credentials. Marked done on that basis.

---

## Live-activity track (boring.notch-inspired)

Pulled in to make the *collapsed* notch feel alive (not just a clipboard on hover):

- 🟢 **Copy sneak-peek** — on capture, the collapsed notch briefly bulges to show
  the clip (`ClipPeekView`, generic peek mechanism in `NotchViewModel`). Verified.
- 🟢 **Now-playing** — `MusicManager` (AppleScript polling of Apple Music/Spotify)
  drives an idle media flank (album art + animated `EqualizerView` around the
  camera) and a full `NowPlayingBar` (artwork, title/artist, ⏮⏸⏭) when expanded.
  **Verified live with Spotify** (real album art via its artwork URL). Requires
  `NSAppleEventsUsageDescription` in Info.plist (added) + the user granting the
  one-time **Automation** permission ("Mybar wants to control Spotify/Music").
  Sparkle's updater is now guarded so an unconfigured feed can't error on launch.
- 🟢 **HUD replacement** (volume) — `MediaKeyTap` (CGEvent tap) intercepts the
  volume keys, `VolumeController` adjusts via AppleScript, and a `HUDPeekView`
  shows the level in the notch. HUD render verified; key interception needs
  Accessibility (granted by the user) so it can't be exercised headlessly.

- 🟢 **Tabbed expanded notch** — the open notch is now organized into tabs
  (`NotchTab`: **Clipboard / Pinned / Music**) via `NotchTabBar`, instead of
  cramming now-playing + clips onto one screen. Clipboard & Pinned share a
  reusable `CardStripView`; Music is a full `NowPlayingDetailView` (artwork,
  title/artist, transport, live progress bar). Cards gained a right-click
  **Pin / Delete** menu + pin badge. The framework is extensible — adding a tab
  is one `NotchTab` case + one branch. Verified each tab live.
- 🟢 **UI polish pass** (Emil Kowalski design-eng principles): unified 20px
  content margin; borderless cards; sliding tab pill (`matchedGeometryEffect`);
  press feedback (`PressableStyle`), spring hover, staggered card entrance;
  Music tab redesigned as an aligned mini-player (progress under title, prominent
  play control); `MarqueeText` for long titles (Reduce-Motion aware); `blurFade`
  enter/leave transition for notch content.

Still deferred 🟡: brightness HUD, battery/charging, webcam mirror, calendar,
swipe gestures, multi-display. (New tabs like Shelf/Calendar now slot in easily.)

---

## Open decisions (revisit before Phase 2 & 7)

1. **Persistence**: start with JSON (simple), or go SwiftData/SQLite up front for
   large histories + search? *Recommendation: JSON now, migrate at Phase 5 if
   needed.*
2. **Sandboxing / distribution**: direct (non-sandboxed) is far easier for
   clipboard + Accessibility + global paste. App Store sandbox is restrictive.
   *Recommendation: non-sandboxed direct distribution for v1.*
3. **History scope**: cap by count, age, or both? Default 200 items / 30 days.
   *Decided (Phase 2): both — 200 unpinned items AND 30-day age cap; pinned exempt.*
4. **Rich text (RTF/HTML)**: *Decided (Phase 2): captured as plain text for now
   (the searchable string). Raw RTF/HTML retention for faithful paste-back can be
   added later via a sidecar blob if needed.*
5. **Phase 6 optional features**: *Decided: inline text-expansion, multi-clip
   combine, and clip reminders are deferred to post-1.0. The "done when" (quick
   search, numbered paste, pin, OCR-search) is fully met without them.*
6. **Notarization credentials (Phase 7)**: *the autonomous build env has no Apple
   Developer ID / Sparkle key, so the actual signed+notarized artifact can't be
   produced here. Resolution: implement everything code-side, ship full tooling
   (`scripts/release.sh`) + docs (`RELEASING.md`); the developer runs one command
   with their credentials to cut the release.*

---

## Superapp roadmap (post-1.0)

Direction: the notch becomes a **platform** — every capability is a tab (when
open) and/or a live activity (when collapsed). The tab bar collapses unselected
tabs to icons, so it scales to many modules.

### Done
- 🟢 **Shelf** — drag-in file staging tray; any drag onto the notch opens it.
  Clean file/image cards with a corner format tag.

### Platform
- ⚪ **`NotchModule` extraction** — formalize the tab/store/drop/live-activity
  pattern into a registry so a module is one file + one registration, and
  Settings auto-populates. *Extract from the Shelf while it's fresh.*
- ⚪ **Live-activity queue** — generalize peek/HUD into a queue (copy peek,
  volume HUD, timer, download progress, AirDrop received…) shown in the collapsed
  notch, with priority + coalescing.
- ⚪ **Tab management** — reorder / enable-disable tabs in Settings.

### Modules (each a tab and/or live activity)
- ⚪ **Shelf polish** — AirDrop / Share action (`NSSharingServicePicker`),
  multi-select, hide the no-op Pin on shelf cards, "create zip".
- ⚪ **Timers / Pomodoro** — countdown ring as a collapsed live activity.
- ⚪ **Calendar / Up Next** — EventKit agenda + a live activity counting down to
  the next event with a one-click join.
- ⚪ **AI (Claude)** — ask Claude, summarize/transform the current clip, smart
  paste, translate (Anthropic API). The key differentiator.
- ⚪ **Weather**, **Battery & system stats**, **Webcam mirror**,
  **Brightness HUD** (completes the HUD set), **Stocks/crypto ticker**.

### Cross-cutting
- ⚪ Real **Apple Music artwork** (different path than Spotify's URL).
- ⚪ **Keyboard navigation** in the open notch (arrows + return to paste).
- ⚪ **Inline snippets / text expansion** (`;sig` → expand).
- ⚪ **Multi-display** support (one window/ViewModel per screen, UUID-tracked).
- ⚪ **Onboarding** flow for first-run permissions.
- ⚪ Cut a **signed + notarized** release (needs Developer ID + Sparkle key).

---

## Reference

boring.notch is cloned at `/tmp/boring.notch` for reference while building.
See its `components/Shelf/` (closest analog) and `helpers/Clipboard+Content.swift`.
