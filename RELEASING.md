# Releasing Mybar

Mybar ships as a **direct download** (not the Mac App Store), so it must be
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
  xcrun notarytool store-credentials MybarNotary \
    --apple-id "you@example.com" --team-id TEAMID --password <app-specific-password>
  ```

### 2. Sparkle signing keys
Sparkle signs updates with an EdDSA key so clients can verify them.
- Get Sparkle's tools (e.g. download a Sparkle release, or
  `swift run --package-path .build/checkouts/Sparkle generate_keys`).
- Run `./bin/generate_keys` once. It stores the **private** key in your keychain
  and prints the **public** key.
- Put the public key in `project.yml` under the target's `info.properties`:
  ```yaml
  SUPublicEDKey: "<base64 public key>"
  SUFeedURL: "https://your.site/mybar/appcast.xml"
  SUEnableAutomaticChecks: true
  ```
- Re-run `xcodegen generate`.

## Cutting a release

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Build, sign, notarize, and package:
   ```sh
   DEV_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
   ```
   This produces a notarized, stapled `Mybar.zip`.
3. Sign the zip for Sparkle and grab the EdDSA signature + length:
   ```sh
   ./bin/sign_update Mybar.zip
   ```
4. Add an `<item>` to `appcast.xml` with the new version, the signature, and the
   download URL, then upload `Mybar.zip` and `appcast.xml` to the host that
   `SUFeedURL` points at.
5. Existing installs see the update on their next check (or via
   **Check for Updates…** in the menu/Settings).

## Notes
- Distribution decision: **non-sandboxed direct download** (see `ROADMAP.md`
  Open Decisions) — required because clipboard polling, Accessibility paste-back,
  and security-scoped bookmarks are heavily restricted under the App Store
  sandbox.
- Hardened runtime is already enabled (`ENABLE_HARDENED_RUNTIME`). Notarization
  requires it.
- The app currently has placeholder `SUFeedURL` and an empty `SUPublicEDKey`, so
  **Check for Updates…** will report an error until the steps above are done.
  Everything else (the updater wiring, menu items, UI) is in place.
