#!/bin/bash
set -euo pipefail

# ─── Config ───
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/SplitMux.xcodeproj"
SCHEME="SplitMux"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/SplitMux.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/SplitMux.dmg"
KEYCHAIN_PROFILE="SplitMux-Notary"
TEAM_ID="2XGP34AR96"
SIGNING_IDENTITY="Developer ID Application: DENG LI (2XGP34AR96)"

# GitHub
GITHUB_REPO="MengnanTech/SplitMux"

# Read version from project.yml
VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
BUILD_NUM=$(grep 'CURRENT_PROJECT_VERSION' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*: *\([0-9]*\)/\1/')

echo "══════════════════════════════════════════"
echo "  SplitMux Release v${VERSION} (build ${BUILD_NUM})"
echo "══════════════════════════════════════════"
echo ""

# ─── Clean ───
echo "🧹 Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_PATH"

# ─── Archive ───
echo "📦 Archiving..."
xcodebuild -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  -quiet

echo "✅ Archive complete"

# ─── Export (manual codesign) ───
echo "📤 Exporting and signing app..."
APP_SRC="$ARCHIVE_PATH/Products/Applications/SplitMux.app"
APP_DST="$EXPORT_PATH/SplitMux.app"
cp -R "$APP_SRC" "$APP_DST"

# Sign all nested frameworks/bundles first, then the app itself
echo "  Signing nested components..."
find "$APP_DST" -type d \( -name "*.framework" -o -name "*.xpc" -o -name "*.app" -o -name "*.dylib" \) -print0 | \
  while IFS= read -r -d '' component; do
    codesign --force --options runtime --timestamp \
      --sign "$SIGNING_IDENTITY" "$component" 2>/dev/null || true
  done

# Sign any dylibs directly
find "$APP_DST" -name "*.dylib" -print0 | \
  while IFS= read -r -d '' dylib; do
    codesign --force --options runtime --timestamp \
      --sign "$SIGNING_IDENTITY" "$dylib" 2>/dev/null || true
  done

# Sign the main app
echo "  Signing main app..."
codesign --force --deep --options runtime --timestamp \
  --sign "$SIGNING_IDENTITY" "$APP_DST"

# Verify signature
codesign --verify --deep --strict "$APP_DST"
echo "✅ Signing verified"

# Strip provenance xattr (blocks hdiutil DMG creation on macOS)
xattr -cr "$APP_DST"

# ─── Create DMG (drag-to-install style) ───
echo "💿 Creating DMG..."
rm -f "$DMG_PATH"

create-dmg \
  --volname "SplitMux" \
  --volicon "$APP_DST/Contents/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "SplitMux.app" 180 170 \
  --hide-extension "SplitMux.app" \
  --app-drop-link 480 170 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_DST"

echo "✅ DMG created (drag-to-install)"

# ─── Notarize ───
echo "🔏 Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

# ─── Staple ───
echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

# ─── Sparkle Appcast ───
echo "📡 Generating Sparkle appcast..."
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Sparkle/bin/generate_appcast" -type f 2>/dev/null | head -1)
APPCAST_DIR="$BUILD_DIR/appcast"
mkdir -p "$APPCAST_DIR"

# Use versioned DMG name so appcast URL matches the uploaded file
VERSIONED_DMG="SplitMux-${VERSION}.dmg"
cp "$DMG_PATH" "$APPCAST_DIR/$VERSIONED_DMG"

if [ -n "${SPARKLE_BIN:-}" ] && [ -x "$SPARKLE_BIN" ]; then
  "$SPARKLE_BIN" --download-url-prefix "https://github.com/$GITHUB_REPO/releases/download/v${VERSION}/" "$APPCAST_DIR"
  echo "✅ Appcast generated"
else
  echo "❌ Sparkle generate_appcast not found. Build in Xcode first."
  exit 1
fi

# ─── GitHub Release ───
echo "🐙 Creating GitHub Release..."
RELEASE_NOTES=$(git log --pretty=format:"- %s" "$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)"..HEAD 2>/dev/null || echo "- v${VERSION} release")

if gh release view "v${VERSION}" --repo "$GITHUB_REPO" &>/dev/null; then
  echo "  Release v${VERSION} already exists, uploading asset..."
  gh release upload "v${VERSION}" "$APPCAST_DIR/$VERSIONED_DMG" --repo "$GITHUB_REPO" --clobber
else
  gh release create "v${VERSION}" "$APPCAST_DIR/$VERSIONED_DMG" \
    --repo "$GITHUB_REPO" \
    --title "v${VERSION}" \
    --notes "$RELEASE_NOTES"
fi
echo "✅ GitHub Release published"

# ─── Commit appcast.xml to repo ───
echo "📡 Committing appcast.xml to repo..."
cp "$APPCAST_DIR/appcast.xml" "$PROJECT_DIR/appcast.xml"
cd "$PROJECT_DIR"
git add appcast.xml
git commit -m "chore: update appcast.xml for v${VERSION}" || echo "  (appcast unchanged, skipping commit)"
git push origin main
echo "✅ Appcast pushed to GitHub"

echo ""
echo "══════════════════════════════════════════"
echo "  ✅ SplitMux v${VERSION} released!"
echo ""
echo "  GitHub:  https://github.com/$GITHUB_REPO/releases/tag/v${VERSION}"
echo "  DMG:     https://github.com/$GITHUB_REPO/releases/download/v${VERSION}/$VERSIONED_DMG"
echo "  Appcast: https://raw.githubusercontent.com/$GITHUB_REPO/main/appcast.xml"
echo "══════════════════════════════════════════"
