#!/bin/bash
set -e

APP_NAME="Handy"
APPEX_NAME="Handy Extension"
APP_BUNDLE="$APP_NAME.app"
APPEX_BUNDLE="$APPEX_NAME.appex"
PLUGINSDIR="$APP_BUNDLE/Contents/PlugIns"
DMG_NAME="$APP_NAME.dmg"
TMP_DMG="/tmp/handy-installer-rw.dmg"
VOLUME="/Volumes/$APP_NAME"
SDK=$(xcrun --sdk macosx --show-sdk-path)
TARGET="$(uname -m)-apple-macos13.0"

# ── Signing configuration ─────────────────────────────────────────────────────
# SIGNING_IDENTITY controls how the app is signed:
#   "-"  (default)  → ad-hoc signing. Works for LOCAL testing only. Permissions
#                     reset on each reinstall; Gatekeeper shows a warning.
#   "Developer ID Application: Your Name (TEAMID)"
#                   → real distribution. Permissions persist, no Gatekeeper
#                     warning, and the build can be notarized.
#
# To go distributable: enroll in the Apple Developer Program, then run:
#   SIGNING_IDENTITY="Developer ID Application: …" bash build.sh
# (or export it in your shell). Nothing else in this script needs to change.
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

if [ "$SIGNING_IDENTITY" = "-" ]; then
    RELEASE_FLAGS=""                                # ad-hoc: local dev only
    SIGN_MODE="ad-hoc (local testing)"
else
    # Hardened Runtime + secure timestamp are required for notarization.
    RELEASE_FLAGS="--options runtime --timestamp"
    SIGN_MODE="$SIGNING_IDENTITY"
fi

echo "Building $APP_NAME  [sign: $SIGN_MODE]..."

# ── Phase 1: Type-check (fast; catches compile errors before touching the bundle)
echo "Type-checking..."
swiftc -typecheck \
    "Sources/App/main.swift" \
    "Sources/App/SettingsView.swift" \
    "Sources/App/EventTap.swift" \
    "Sources/App/FinderCutPaste.swift" \
    "Sources/App/KeepAwake.swift" \
    "Sources/App/Bluetooth.swift" \
    -sdk "$SDK" -target "$TARGET" \
    -framework Cocoa -framework SwiftUI -framework ServiceManagement \
    2>&1 | sed 's/^/  /'
if [ "${PIPESTATUS[0]}" -ne 0 ]; then echo "Type-check failed. Aborting."; exit 1; fi

swiftc -typecheck \
    "Sources/Extension/FinderSyncExtension.swift" \
    -sdk "$SDK" -target "$TARGET" \
    -framework Cocoa -framework FinderSync \
    2>&1 | sed 's/^/  /'
if [ "${PIPESTATUS[0]}" -ne 0 ]; then echo "Type-check failed. Aborting."; exit 1; fi

# ── Phase 2: Logic unit tests
echo "Running tests..."
TEST_BIN="/tmp/handy-tests-$$"
swiftc "Tests/HandyTests.swift" -o "$TEST_BIN" 2>&1 | sed 's/^/  /'
if [ "${PIPESTATUS[0]}" -ne 0 ]; then echo "Test compilation failed. Aborting."; exit 1; fi
"$TEST_BIN"
TEST_RESULT=$?
rm -f "$TEST_BIN"
if [ "$TEST_RESULT" -ne 0 ]; then echo "Tests failed. Aborting."; exit 1; fi

# ── Clean ─────────────────────────────────────────────────────────────────────
rm -rf "$APP_BUNDLE"

# ── Bundle structure ──────────────────────────────────────────────────────────
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$PLUGINSDIR/$APPEX_BUNDLE/Contents/MacOS"

# ── Icon ──────────────────────────────────────────────────────────────────────
echo "Generating icon..."
swift create_icon.swift > /dev/null
iconutil -c icns Handy.iconset -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf Handy.iconset

# ── Compile main app ──────────────────────────────────────────────────────────
echo "Compiling app..."
swiftc "Sources/App/main.swift" \
       "Sources/App/SettingsView.swift" \
       "Sources/App/EventTap.swift" \
       "Sources/App/FinderCutPaste.swift" \
       "Sources/App/KeepAwake.swift" \
       "Sources/App/Bluetooth.swift" \
    -sdk "$SDK" \
    -target "$TARGET" \
    -framework Cocoa \
    -framework SwiftUI \
    -framework ServiceManagement \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cp "Sources/App/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# ── Compile FinderSync extension ──────────────────────────────────────────────
echo "Compiling FinderSync extension..."
swiftc "Sources/Extension/FinderSyncExtension.swift" \
    -sdk "$SDK" \
    -target "$TARGET" \
    -parse-as-library \
    -module-name FinderSyncExtension \
    -framework Cocoa \
    -framework FinderSync \
    -Xlinker -lcompression \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$PLUGINSDIR/$APPEX_BUNDLE/Contents/MacOS/$APPEX_NAME"

cp "Sources/Extension/Info.plist" "$PLUGINSDIR/$APPEX_BUNDLE/Contents/Info.plist"

# ── Sign (inside-out: extension → [frameworks] → app) ────────────────────────
# Nested code must be signed before the code that contains it. When Sparkle is
# added, its framework gets signed here, between the extension and the app.
echo "Signing ($SIGN_MODE)..."
codesign --force $RELEASE_FLAGS --sign "$SIGNING_IDENTITY" \
    --entitlements "Sources/Extension/extension.entitlements" \
    "$PLUGINSDIR/$APPEX_BUNDLE"
codesign --force $RELEASE_FLAGS --sign "$SIGNING_IDENTITY" \
    --entitlements "Sources/App/app.entitlements" \
    "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE"

# ── Phase 3: Post-build structure checks
echo "Verifying bundle..."
FAIL=0
checks=(
    "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    "$APP_BUNDLE/Contents/Info.plist"
    "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    "$PLUGINSDIR/$APPEX_BUNDLE/Contents/MacOS/$APPEX_NAME"
    "$PLUGINSDIR/$APPEX_BUNDLE/Contents/Info.plist"
)
for f in "${checks[@]}"; do
    if [ -e "$f" ]; then
        printf "  ✓  %s\n" "${f#$APP_BUNDLE/}"
    else
        printf "  ✗  MISSING: %s\n" "${f#$APP_BUNDLE/}"
        FAIL=1
    fi
done
# Verify signatures
codesign -v "$PLUGINSDIR/$APPEX_BUNDLE" 2>/dev/null \
    && echo "  ✓  Extension signature valid" \
    || { echo "  ✗  Extension signature invalid"; FAIL=1; }
codesign -v "$APP_BUNDLE" 2>/dev/null \
    && echo "  ✓  App signature valid" \
    || { echo "  ✗  App signature invalid"; FAIL=1; }
if [ "$FAIL" -ne 0 ]; then echo "Bundle verification failed. Aborting."; exit 1; fi

# ── Package DMG ───────────────────────────────────────────────────────────────
echo "Packaging installer..."

TMP_DIR=$(mktemp -d)
cp -r "$APP_BUNDLE" "$TMP_DIR/"
ln -s /Applications "$TMP_DIR/Applications"

[ -d "$VOLUME" ] && hdiutil detach "$VOLUME" -quiet 2>/dev/null || true
rm -f "$TMP_DMG"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$TMP_DIR" \
    -ov -format UDRW -size 20m \
    "$TMP_DMG" > /dev/null

hdiutil attach "$TMP_DMG" -mountpoint "$VOLUME" -noautoopen -quiet
sleep 1

osascript <<APPLESCRIPT || true
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 150, 700, 430}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set position of item "$APP_NAME.app" of container window to {140, 140}
        set position of item "Applications" of container window to {360, 140}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

sleep 1
hdiutil detach "$VOLUME" -quiet

rm -f "$DMG_NAME"
hdiutil convert "$TMP_DMG" \
    -format UDZO -imagekey zlib-level=9 \
    -o "$DMG_NAME" > /dev/null

rm -rf "$TMP_DIR" "$TMP_DMG"

echo ""
echo "Done! Opening installer..."
open "$DMG_NAME"
