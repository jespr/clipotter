# Releasing Transcript

Direct distribution with auto-updates via [Sparkle]. GitHub Releases host the
`.dmg`; GitHub Pages hosts the Sparkle appcast + landing page.

## One-time setup

1. **Create the GitHub repo** (the release script tags, pushes, and creates releases):
   ```sh
   gh repo create jespr/transcript --source . --public --push
   ```
2. **Enable GitHub Pages**: repo Settings → Pages → Source = **GitHub Actions**.
   The `Deploy website` workflow publishes `website/` to
   `https://jespr.github.io/transcript/` (this is the `SUFeedURL` baked into the app).
3. **Notarization credentials** (needs an [app-specific password]):
   ```sh
   xcrun notarytool store-credentials "AC_PASSWORD" \
     --apple-id "hi@jespr.com" --team-id "CA629ESX52" --password "<app-specific-password>"
   ```
4. **`.env`** — already filled in for this machine (Team ID, Apple ID, signing
   identity). It's gitignored. See `.env.example` for the shape.

The Sparkle EdDSA signing key already exists in your login Keychain; its public
key is in `project.yml` (`SUPublicEDKey`). `sign_update` uses the private key
automatically. Keep that key — losing it means clients can't verify updates.

## Cutting a release

1. Add a dated section to `CHANGELOG.md`:
   ```
   ## [1.1.0] - 2026-06-10
   - What changed
   ```
2. Bump `MARKETING_VERSION` in `project.yml` (optional — the script passes the
   version to `xcodebuild`, but keeping it in sync is tidy).
3. Run:
   ```sh
   ./scripts/release.sh 1.1.0          # full release
   ./scripts/release.sh --dry-run 1.1.0 # build + sign + verify only
   ```

The script: regenerates the Xcode project → archives → exports (Developer ID,
hardened runtime) → verifies signing → builds a DMG → notarizes + staples →
Gatekeeper-assesses → tags → writes `website/appcast.xml` + `changelog.html` and
pushes → creates the GitHub Release with the DMG.

## How updates reach users

The app reads `SUFeedURL` (`…/appcast.xml`) on a schedule. The appcast's
`<enclosure>` points at the GitHub Release DMG and carries the EdDSA signature;
Sparkle verifies it against `SUPublicEDKey` before installing. "Check for
Updates…" is in the app menu.

[Sparkle]: https://sparkle-project.org
[app-specific password]: https://support.apple.com/en-us/102654
