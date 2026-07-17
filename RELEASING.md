# Releasing Perch

Perch ships as a **unsigned direct download** via GitHub Releases. Since we
don't have an Apple Developer account yet, the app is built without code
signing. Users bypass Gatekeeper once on first launch.

## Cutting a release

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Commit and push, then tag:
   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```
3. The GitHub Action builds `Perch.dmg` and creates a draft release automatically.
4. Publish the draft on https://github.com/Arunava-K/Perch/releases.

## User installation

**Direct download:**
1. Download `Perch.dmg` from a release
2. Drag `Perch.app` to `/Applications`
3. Run once:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Perch.app
   ```
4. Launch normally from `/Applications`

**Homebrew (once set up):**
```sh
brew install --cask arunava-k/perch/perch --no-quarantine
```

## Optional: paid Developer ID + Sparkle later

If you enroll in the Apple Developer Program ($99/yr) later:

1. Create a Developer ID Application certificate in Xcode → Settings → Accounts.
2. Generate Sparkle keys: `./bin/generate_keys`
3. Put the public key and feed URL in `project.yml`:
   ```yaml
   SUPublicEDKey: "<base64 key>"
   SUFeedURL: "https://your.site/perch/appcast.xml"
   ```
4. Re-enable hardened runtime in `project.yml` (set `Release` → `ENABLE_HARDENED_RUNTIME: YES`)
5. Update `scripts/release.sh` to restore the signing/notarization steps from git history
6. Run: `DEV_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh`

## Notes
- Distribution decision: **non-sandboxed direct download** — required because
  clipboard polling, Accessibility paste-back, and security-scoped bookmarks are
  heavily restricted under the App Store sandbox.
- The in-app "Check for Updates…" button is dormant (shows a "not configured"
  message) until Sparkle keys are set up.
- Package versions are pinned with `exactVersion` in `project.yml` so release
  builds do not silently pick newer SPM tags.
