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

# ─── Create DMG ───
echo "💿 Creating DMG..."
hdiutil create -volname "SplitMux" \
  -srcfolder "$APP_DST" \
  -ov -format UDZO \
  "$DMG_PATH" \
  -quiet

echo "✅ DMG created"

# ─── Notarize ───
echo "🔏 Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

# ─── Staple ───
echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo ""
echo "══════════════════════════════════════════"
echo "  ✅ Done! Notarized DMG ready at:"
echo "  $DMG_PATH"
echo "══════════════════════════════════════════"
