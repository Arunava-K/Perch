# Perch — Product Roadmap

**Positioning:** Free, open-source macOS notch utility. Clipboard-first “superapp”
that lives in the hardware notch — not a music toy with extras bolted on.

**License / money:** OSS + free forever. No freemium gates. Optional later:
GitHub Sponsors / Ko-fi (community support only).

**Status:** Feature-rich v0.1 — clipboard stack is deep; notch platform is solid;
docs and distribution still lag the product.

---

## 1. Market map

### Notch “Dynamic Island” apps

| Product | Model | Strengths | Gaps vs Perch |
|--------|--------|-----------|----------------|
| **[Boring Notch](https://github.com/TheBoredTeam/boring.notch)** (~10k★, GPL, free/unsigned) | Music + shelf + calendar + HUD + mirror | Community, polish, mediaremote, Homebrew cask | Clipboard is not the product; no vault/OCR/semantic search |
| **NotchNook / similar paid** | Polished paid notch UI | Design, App Store-ish install | Closed, paid, shallow clipboard |
| **DynamicNotchKit / DIY kits** | Dev libraries | Extensibility for builders | Not end-user products |

### Clipboard managers

| Product | Model | Strengths | Gaps vs Perch |
|--------|--------|-----------|----------------|
| **[Maccy](https://github.com/p0deje/Maccy)** (~21k★, MIT, free + Homebrew) | Keyboard-first history | Simple, trusted, paste/search excellence | No notch UX, no shelf/live activities |
| **Paste / PasteNow / CopyClip** | Paid / freemium | UX polish, sync (some) | Closed; not notch-native |
| **Raycast Clipboard** | Raycast free tier | Palette UX, extensions | Requires Raycast; not ambient notch |
| **Supaste** | Paid notch clipboard | Closest *product* inspiration | Closed, paid |

### Adjacent utilities (feature overlap, not full competitors)

| Area | Examples | What users expect |
|------|----------|-------------------|
| System monitors | Stats, iStat Menus, Menuwhere | Live CPU/GPU/mem, top processes |
| Focus / timers | Stretchly, Session, native Focus | Pomodoro + ambient countdown |
| Calendar | Fantastical, Calendr | Agenda + join links |
| Notifications | Alerter hacks, Bannerless | Replace/mirror banners |
| Media HUDs | Background Music, custom HUDs | Volume/brightness in custom chrome |

### What the market rewards (esp. free OSS)

1. **One killer daily habit** (Maccy = paste history; Boring Notch = music in the notch).
2. **Trust** — clear permissions, no telemetry drama, easy uninstall.
3. **Install path** — Homebrew + (ideally) notarized DMG; quarantine docs if unsigned.
4. **Restraint** — modules on by default only if they’re excellent; rest opt-in.
5. **Docs that match the binary** — README/ROADMAP drift kills contributor trust.

---

## 2. Where Perch already wins

Unique combination **none of the above fully ship**:

| Capability | Perch | Boring Notch | Maccy |
|------------|-------|--------------|-------|
| Notch-native clipboard strip + paste-back | ✅ | weak | ❌ |
| SQLite history + image blobs | ✅ | — | lighter |
| OCR + on-device semantic search | ✅ | ❌ | ❌ |
| Vault (AES-GCM + Touch ID) | ✅ | ❌ | limited |
| Library window + Quick Search palette | ✅ | ❌ | palette only |
| Shelf (drag staging) | ✅ basic | ✅ stronger (AirDrop) | ❌ |
| Music / timer / calendar / system / weather / webcam / HUD | ✅ | ✅ (music stronger) | ❌ |
| Free + open source | ✅ | ✅ | ✅ |

**Thesis:** Be the **clipboard brain in the notch**, with optional live activities —
not another music-first Boring Notch clone, and not a menu-bar-only Maccy clone.

---

## 3. Strategic principles (free OSS)

1. **Clipboard excellence is non-negotiable.** If paste/search/history loses to Maccy, the notch chrome doesn’t matter.
2. **Default surface stays small.** New modules default off or ear-only until proven.
3. **Permissions are progressive.** First launch: Accessibility for paste. Everything else is Settings opt-in with plain-language “why.”
4. **No cloud required.** On-device only unless a future optional sync is explicitly scoped (and privacy-reviewed).
5. **Ship install friction fixes before vanity features.** Unsigned DMG is fine for early OSS *if* Homebrew + README are excellent.
6. **Don’t chase Boring Notch feature parity.** Steal *patterns* (shelf AirDrop, mediaremote); keep product identity.
7. **AI is optional and BYO-key** if added — never a paid cloud dependency for core features.

---

## 4. Roadmap phases

Legend: 🔵 now · ⚪ next · 🟡 later · 🧊 icebox

---

### Phase A — Open-source launch readiness 🔵

**Goal:** A stranger can discover, install, trust, and contribute without asking you.

| Item | Why | Done when |
|------|-----|-----------|
| Rewrite **README** for Perch (not Mybar / phase checklist) | First impression | Features, screenshots/GIF, install, permissions table, build from source |
| Refresh this **ROADMAP** (this file) | Direction for contributors | Matches code |
| **CONTRIBUTING.md** + issue/PR templates | Community hygiene | Clear “how to build” (`xcodegen` + `xcodebuild`) |
| **LICENSE** explicit in README | OSS signal | SPDX visible |
| **Homebrew cask** (tap or core) | Primary install for power users | `brew install --cask …` works; auto strip quarantine if possible |
| Fix About / GitHub URLs | Trust | Points at real repo |
| First-run **permissions explainer** (1–2 screens) | Drop-off | Accessibility explained; other perms deferred |
| Tag **v0.2.0** release notes | Narrative | “What Perch is” not internal phase numbers |

**Explicitly out of A:** Developer ID / notarization (nice, not required for OSS v0.2 if Homebrew path is solid).

---

### Phase B — Clipboard depth (beat Maccy where it matters) 🔵

**Goal:** Daily drivers stop keeping Maccy installed “just in case.”

| Item | Why | Done when |
|------|-----|-----------|
| Quick Search = **keyword + semantic** (parity with Library) | Power users live in ⌃⌘V | Same ranking quality as Library |
| **Ignore next copy** + pause capture (⌥-click menu pattern from Maccy) | Sensitive workflows | One-shot and sticky pause |
| **Pin shortcuts** stable (optional letter hotkeys) | Muscle memory | Pinned clips reachable without hunting |
| **Plain-text paste** variants in palette (⌥⏎) | Dev/design workflows | Documented shortcut |
| Image **vault** (encrypt blobs or refuse lock with clear UX) | Security hole today | Locked images don’t sit cleartext |
| Trash retention UI in Settings | Pref exists, half-exposed | User can set purge days |
| Source-app **ignore list** | Noise control | Settings list of bundle IDs |
| Performance pass: large histories (1k+), strip rebuild cost | Scale | No jank opening notch with fat DB |

**Defer in B:** iCloud sync, teams/shared clipboards.

---

### Phase C — Notch platform polish ⚪

**Goal:** Feels like one product, not a pile of modules.

| Item | Why | Done when |
|------|-----|-----------|
| **Shelf v2** — AirDrop/Share, multi-select, zip, remove dead Pin | Boring Notch parity where it helps *clipboard-adjacent* flow | Drag folder of files → share/zip from notch |
| Live-activity **priority matrix** documented + tunable | Timer vs load vs media fights | Settings: order or mute categories |
| **Music** via MediaRemote-style path (not only AppleScript) | Reliability on modern macOS | Spotify/Music art + transport stable |
| Brightness HUD reliability | Complete HUD story | Works on supported hardware; graceful hide otherwise |
| Collapsed **gesture** (optional click → open last tab) | Discoverability | Documented; off by default if noisy |
| Remove or finish dead **RemindersModule** tab path | Code honesty | One reminders story only |
| Multi-display: correct screen / primary-notch policy | Multi-monitor users | Documented behavior; no wrong-screen panel |

---

### Phase D — Distribution maturity ⚪

**Goal:** Install feels like a “real” Mac app without becoming paid.

| Item | Why | Done when |
|------|-----|-----------|
| Optional **Developer ID + notarization** | Gatekeeper happiness | Still free; CI secrets documented |
| **Sparkle** feed (or GitHub Releases updater) | Auto-update for DMG users | “Check for Updates” works |
| Website one-pager (GitHub Pages) | Shareable link | Download + GIF + permissions |
| Crash/log opt-in **local only** or none | Trust | No silent network |

Sponsors badge in README is enough monetization for this phase.

---

### Phase E — Selective new modules 🟡

Only after A–C. Each module must justify notch real estate.

| Module | Priority | Notes |
|--------|----------|-------|
| **Snippets / text expansion** (`;sig`) | High | Clipboard-adjacent; Maccy doesn’t own this well |
| **Multi-clip paste** (stack → one paste) | High | Unique power feature |
| **Bluetooth connect peek** | Medium | Boring Notch roadmap item; low effort delight |
| **Focus / DND status ear** | Medium | Ties to existing notification mirror |
| Stocks/crypto ticker | Low | Noise risk; opt-in only |
| Full notification center replacement | Low | FDA + fragile; keep mirror, don’t boil ocean |

---

### Phase F — AI (optional, opinionated) 🟡

**Do not block core on AI.**

| Approach | Recommendation |
|----------|----------------|
| Cloud Claude/OpenAI with **user API key** | OK as opt-in module: summarize clip, rewrite tone, translate |
| Bundled model | Heavy; skip for now |
| “Smart paste” that needs network always | No — breaks offline/trust story |

**Done when:** “Transform clip…” actions appear in Library/Quick Search context menu; key stored in Keychain; fully off when unset.

---

### Icebox 🧊

- App Store / sandbox (fights clipboard + AX + FDA).
- Windows/Linux.
- Lock-screen widgets (private APIs).
- Extension/plugin marketplace (support cost).
- iCloud clip sync (privacy + conflict UX).
- Inline notch keyboard nav as primary (panel is non-key by design — keep palette).

---

## 5. Suggested sequencing (next ~8–12 weeks)

```
Week 1–2   Phase A: README, Homebrew, CONTRIBUTING, v0.2 story
Week 2–5   Phase B: Quick Search semantic, pause capture, vault images, ignore apps
Week 5–8   Phase C: Shelf v2, music reliability, activity priorities
Week 8–10  Phase D: notarize if keys available; Sparkle or GH updater
Week 10+   Phase E snippets + multi-clip; AI only if demand shows up in issues
```

**Near-term “start Monday” list (concrete):**

1. README + screenshots/GIF for current Perch.
2. Homebrew cask in a tap.
3. Quick Search semantic parity with Library.
4. Pause / ignore-next-copy.
5. Shelf Share + zip; kill no-op pin.
6. Image vault policy.

---

## 6. Success metrics (OSS-appropriate)

Not MRR. Track:

| Signal | Healthy |
|--------|---------|
| GitHub stars / unique clones | Steady growth after README + brew |
| `brew` install count (if available) | Non-zero weekly |
| Issue quality | Repros > “add crypto” drive-bys |
| Permission drop-off (anecdotal) | Users report paste-back works first session |
| “Uninstalled Maccy” comments | Occasional = clipboard thesis working |
| Contributor PRs | Even small docs/fix PRs |

---

## 7. Competitive posture (one paragraph)

**Boring Notch** owns playful media-notch mindshare; **Maccy** owns trusted free clipboard. **Perch** should own *clipboard + ambient Mac context in the notch* — history, paste, vault, and search as the core loop; music/timer/calendar/system as opt-in live activities. Stay free and open; win on depth and taste, not on feature-count races or paid gates.

---

## 8. Reference links

- [Boring Notch](https://github.com/TheBoredTeam/boring.notch)
- [Maccy](https://github.com/p0deje/Maccy)
- [Supaste](https://www.supaste.com/) (paid inspiration)
- Internal: `AGENTS.md` (engineering constraints), `RELEASING.md` (ship process)
