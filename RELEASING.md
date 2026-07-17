# Releasing Perch

Perch ships as a **direct download** (not the Mac App Store), so it must be
**code-signed with a Developer ID and notarized** by Apple, and auto-updates via
**Sparkle**. The steps below require credentials that only you (the developer)
hold — they can't be performed in CI without your secrets.

## One-time setup

### 1. Apple Developer ID
- Enroll in the Apple Developer Program ($99/yr).
- In Xcode → Settings → Accounts, create a **Developer ID Application**
  certificate. Confirm it's in your login keychain:
  ```sh
  security find-identity -v -p codesigning
  ```
- Store notarization credentials once:
  ```sh
  xcrun notarytool store-credentials PerchNotary \
    --apple-id "you@example.com" --team-id TEAMID --password <app-specific-password>
  ```

### 2. Sparkle signing keys
Sparkle signs updates with an EdDSA key so clients can verify them.

1. Download a Sparkle release and copy its tools into `./bin`:
   ```sh
   mkdir -p bin
   # From the Sparkle distribution:
   cp /path/to/Sparkle-*/bin/generate_keys bin/
   cp /path/to/Sparkle-*/bin/sign_update bin/
   chmod +x bin/generate_keys bin/sign_update
   ```
2. Run `./bin/generate_keys` once. It stores the **private** key in your keychain
   and prints the **public** key.
3. Put the public key in `project.yml` under the target's `info.properties`:
   ```yaml
   SUPublicEDKey: "<base64 public key>"
   SUFeedURL: "https://your.site/perch/appcast.xml"
   SUEnableAutomaticChecks: true
   ```
4. Re-run `xcodegen generate`.

Until `SUPublicEDKey` is set, the in-app updater stays dormant and "Check for
Updates…" explains that updates are not configured.

## Cutting a release

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Build a **universal** signed, notarized package:
   ```sh
   DEV_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
   ```
   The script:
   - fails if the Sparkle feed/key are still placeholders (override with
     `ALLOW_UNCONFIGURED_SPARKLE=1` only for non-update test packages)
   - builds for `generic/platform=macOS` (arm64 + x86_64)
   - enables hardened runtime, notarizes, staples, and runs `spctl --assess`
3. Sign the zip for Sparkle and grab the EdDSA signature + length:
   ```sh
   ./bin/sign_update Perch.zip
   ```
4. Add an `<item>` to `appcast.xml` with the new version, the signature, and the
   download URL, then upload `Perch.zip` and `appcast.xml` to the host that
   `SUFeedURL` points at.
5. Existing installs see the update on their next check (or via
   **Check for Updates…** in the menu/Settings).

## Notes
- Distribution decision: **non-sandboxed direct download** — required because
  clipboard polling, Accessibility paste-back, and security-scoped bookmarks are
  heavily restricted under the App Store sandbox.
- Local Debug builds keep hardened runtime **off** (self-signed "Perch Dev"
  identity). Release builds and `scripts/release.sh` enable it for notarization.
- Package versions are pinned with `exactVersion` in `project.yml` so release
  builds do not silently pick newer SPM tags.
