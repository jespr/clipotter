#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release.sh [--dry-run] <version>
#
# Options:
#   --dry-run  Build, sign, and verify only. Skips notarization, GitHub, and appcast.
#
# Reads credentials from .env in the project root (see .env.example):
#   APPLE_TEAM_ID          — Apple Developer Team ID
#   APPLE_ID               — Apple ID email for notarization
#   SIGNING_IDENTITY_NAME  — e.g. "Jesper Christiansen"
#
# One-time setup (notarization):
#   xcrun notarytool store-credentials "AC_PASSWORD" \
#     --apple-id "<APPLE_ID>" --team-id "<APPLE_TEAM_ID>" --password "<app-specific-password>"

APP_NAME="ClipOtter"
BUNDLE_ID="com.jespr.ClipOtter"
GITHUB_REPO="jespr/clipotter"          # used for release asset + appcast enclosure URLs
MIN_SYSTEM_VERSION="26.0"               # macOS required to run; appears in appcast

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

if [ -f "$ROOT_DIR/.env" ]; then
  set -a
  source "$ROOT_DIR/.env"
  set +a
fi

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
  shift
fi

VERSION="${1:?Usage: ./scripts/release.sh [--dry-run] <version>}"

TEAM_ID="${APPLE_TEAM_ID:?Set APPLE_TEAM_ID in .env}"
SIGNING_IDENTITY="Developer ID Application: ${SIGNING_IDENTITY_NAME:?Set SIGNING_IDENTITY_NAME in .env} ($TEAM_ID)"
APPLE_ID="${APPLE_ID:?Set APPLE_ID in .env}"

# --- Changelog helpers --------------------------------------------------------

# Extract a version's bullets as an HTML <ul> (for the appcast <description>).
extract_changelog() {
  local version="$1" changelog="$2" in_section=false html="<ul>"
  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ \[${version}\] ]]; then in_section=true; continue; fi
    if $in_section && [[ "$line" =~ ^##\  ]]; then break; fi
    if $in_section && [[ "$line" =~ ^-\ (.+) ]]; then html+="<li>${BASH_REMATCH[1]}</li>"; fi
  done < "$changelog"
  html+="</ul>"
  [ "$html" = "<ul></ul>" ] && echo "" || echo "$html"
}

# Extract a version's bullets as raw markdown (for the GitHub release notes).
extract_changelog_markdown() {
  local version="$1" changelog="$2" in_section=false md=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ \[${version}\] ]]; then in_section=true; continue; fi
    if $in_section && [[ "$line" =~ ^##\  ]]; then break; fi
    if $in_section && [[ "$line" =~ ^-\ (.+) ]]; then md+="- ${BASH_REMATCH[1]}"$'\n'; fi
  done < "$changelog"
  echo "$md"
}

# --- DMG -----------------------------------------------------------------------

create_dmg_file() {
  local output_path="$1"
  rm -f "$output_path"
  create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 600 360 \
    --icon-size 140 \
    --icon "$APP_NAME.app" 160 170 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 440 170 \
    --no-internet-enable \
    --format UDZO \
    "$output_path" \
    build/export/"$APP_NAME".app || true
  [ -f "$output_path" ] || { echo "❌ DMG creation failed"; exit 1; }
}

# --- Preflight -----------------------------------------------------------------

command -v create-dmg >/dev/null || { echo "❌ create-dmg not found. brew install create-dmg"; exit 1; }
if ! $DRY_RUN; then
  command -v gh >/dev/null || { echo "❌ gh not found. brew install gh"; exit 1; }
  if ! xcrun notarytool history --keychain-profile "AC_PASSWORD" >/dev/null 2>&1; then
    echo "❌ notarytool keychain profile \"AC_PASSWORD\" not set up. Run:"
    echo "   xcrun notarytool store-credentials \"AC_PASSWORD\" --apple-id \"$APPLE_ID\" --team-id \"$TEAM_ID\" --password \"<app-specific-password>\""
    exit 1
  fi
fi

# --- Build + export ------------------------------------------------------------

echo "🔨 Building $APP_NAME v$VERSION..."
xcodegen generate

rm -rf build
mkdir -p build

xcodebuild -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -archivePath "build/$APP_NAME.xcarchive" \
  -allowProvisioningUpdates \
  archive \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION"

sed "s/\${APPLE_TEAM_ID}/$TEAM_ID/g" ExportOptions.plist > build/ExportOptions.plist
xcodebuild -exportArchive \
  -archivePath "build/$APP_NAME.xcarchive" \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates

# Developer ID export signs the app + embedded Sparkle.framework (and its XPC
# services) with hardened runtime. The app is not sandboxed, so no entitlement
# re-signing is needed — just verify the chain.
codesign --verify --deep --strict --verbose=2 "build/export/$APP_NAME.app"
echo "✅ Code signature verified (deep + strict)."

echo "📦 Creating DMG..."
create_dmg_file "build/$APP_NAME.dmg"

if $DRY_RUN; then
  echo "🏁 Dry run complete."
  echo "   App: build/export/$APP_NAME.app"
  echo "   DMG (signed, NOT notarized): build/$APP_NAME.dmg"
  echo "   Gatekeeper will warn on first open — right-click the app → Open,"
  echo "   or clear quarantine: xattr -dr com.apple.quarantine build/$APP_NAME.dmg"
  exit 0
fi

# --- Notarize + staple ---------------------------------------------------------

echo "🔏 Notarizing..."
xcrun notarytool submit "build/$APP_NAME.dmg" --keychain-profile "AC_PASSWORD" --wait

echo "📎 Stapling..."
xcrun stapler staple "build/export/$APP_NAME.app"
rm "build/$APP_NAME.dmg"
create_dmg_file "build/$APP_NAME.dmg"
xcrun stapler staple "build/$APP_NAME.dmg" || echo "⚠️  DMG staple delay (app inside is stapled)."

spctl --assess --type execute --verbose "build/export/$APP_NAME.app"
echo "✅ Gatekeeper assessment passed."

# --- Tag -----------------------------------------------------------------------

echo "🏷️  Tagging v$VERSION..."
git tag "v$VERSION"
git push --tags

# --- Sparkle appcast -----------------------------------------------------------

echo "📡 Generating Sparkle appcast..."
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*/SourcePackages/artifacts/sparkle/Sparkle/bin -maxdepth 0 2>/dev/null | head -1)
[ -z "$SPARKLE_BIN" ] && SPARKLE_BIN=$(find build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin -maxdepth 0 2>/dev/null | head -1)
[ -n "$SPARKLE_BIN" ] || { echo "❌ Could not locate Sparkle bin (sign_update)."; exit 1; }

SIGNATURE=$("$SPARKLE_BIN/sign_update" "build/$APP_NAME.dmg" 2>&1)
ED_SIG=$(echo "$SIGNATURE" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGNATURE" | grep -o 'length="[^"]*"' | cut -d'"' -f2)
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

RELEASE_NOTES=$(extract_changelog "$VERSION" "CHANGELOG.md")
[ -z "$RELEASE_NOTES" ] && echo "⚠️  No CHANGELOG.md entry for v$VERSION — appcast will have no release notes."

# Preserve existing items, dropping any matching this version (in case of re-release).
EXISTING_ITEMS=""
if [ -f website/appcast.xml ]; then
  EXISTING_ITEMS=$(awk '
    /<item>/ { buf=""; capture=1 }
    capture { buf = buf $0 "\n" }
    /<\/item>/ {
      capture=0
      if (buf !~ /<sparkle:version>'"$VERSION"'</) printf "%s", buf
    }
  ' website/appcast.xml)
fi

DESC_ELEMENT=""
[ -n "$RELEASE_NOTES" ] && DESC_ELEMENT="      <description><![CDATA[$RELEASE_NOTES]]></description>"

cat > build/appcast.xml << APPCAST
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
  <channel>
    <title>$APP_NAME</title>
    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_SYSTEM_VERSION</sparkle:minimumSystemVersion>
      <pubDate>$PUB_DATE</pubDate>
$DESC_ELEMENT
      <enclosure
        url="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$APP_NAME.dmg"
        sparkle:edSignature="$ED_SIG"
        length="$LENGTH"
        type="application/octet-stream"
      />
    </item>
$EXISTING_ITEMS
  </channel>
</rss>
APPCAST

echo "📡 Updating site (appcast + changelog)..."
cp build/appcast.xml website/appcast.xml
source "$SCRIPT_DIR/lib/changelog-html.sh"
generate_changelog_html
git add website/appcast.xml website/changelog.html
git commit -m "chore: update appcast for v$VERSION" || true
git push

# --- GitHub release ------------------------------------------------------------

echo "🚀 Creating GitHub Release..."
CHANGELOG_MD=$(extract_changelog_markdown "$VERSION" "CHANGELOG.md")
if [ -n "$CHANGELOG_MD" ]; then
  gh release create "v$VERSION" "build/$APP_NAME.dmg" --title "$APP_NAME v$VERSION" --notes "$CHANGELOG_MD"
else
  gh release create "v$VERSION" "build/$APP_NAME.dmg" --title "$APP_NAME v$VERSION" --generate-notes
fi

echo "✅ Done! Release: https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"
