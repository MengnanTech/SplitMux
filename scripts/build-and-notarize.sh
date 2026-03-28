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

# Remote server
REMOTE="calyx"
REMOTE_DIR="/opt/calyx/splitmux"

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
cp "$DMG_PATH" "$APPCAST_DIR/"

if [ -n "${SPARKLE_BIN:-}" ] && [ -x "$SPARKLE_BIN" ]; then
  "$SPARKLE_BIN" "$APPCAST_DIR"
  echo "✅ Appcast generated"
else
  echo "❌ Sparkle generate_appcast not found. Build in Xcode first."
  exit 1
fi

# ─── Upload to calyx-ai.com ───
echo "🚀 Uploading to calyx-ai.com..."
ssh "$REMOTE" "mkdir -p $REMOTE_DIR/releases"

VERSIONED_DMG="SplitMux-${VERSION}.dmg"
rsync -az --info=progress2 "$DMG_PATH" "$REMOTE:$REMOTE_DIR/releases/$VERSIONED_DMG"
rsync -az "$APPCAST_DIR/appcast.xml" "$REMOTE:$REMOTE_DIR/"

echo "✅ Uploaded to server"

# ─── Configure Nginx (first time only) ───
ssh "$REMOTE" "cat > /tmp/splitmux-nginx.conf << 'NGINX'
# SplitMux update feed & downloads
location /splitmux/ {
    alias $REMOTE_DIR/;
    autoindex off;
}
NGINX

if ! grep -q '/splitmux/' /opt/calyx/nginx/conf.d/calyx-ai.conf 2>/dev/null; then
  echo '  First release — adding Nginx config...'
  # Insert before the last closing brace of the server block
  sed -i '/^}/i \\    include /tmp/splitmux-nginx.conf;' /opt/calyx/nginx/conf.d/calyx-ai.conf
  docker exec calyx-nginx nginx -s reload 2>/dev/null || true
  echo '  Nginx configured'
else
  echo '  Nginx already configured'
fi
"

echo ""
echo "══════════════════════════════════════════"
echo "  ✅ SplitMux v${VERSION} released!"
echo ""
echo "  DMG:     https://calyx-ai.com/splitmux/releases/$VERSIONED_DMG"
echo "  Appcast: https://calyx-ai.com/splitmux/appcast.xml"
echo "══════════════════════════════════════════"
