#!/bin/bash
# =============================================================================
# MicroCode AI (Standalone Edition) — release packager
#
# MicroCode AI ships from the same repository and the same commit as MicroCode.
# The standalone edition is selected at runtime by `AppEdition.isStandaloneAI`
# (bundle id `com.dotmini.microcode.ai` / Info.plist `MicroCodeStandaloneAI`),
# so the installer is the Universal Lite build re-branded and re-signed:
# no second compile, and both products always match the tagged source.
#
# Usage: ./package_ai_from_lite.sh <Dotmini_MicroCode_Lite.dmg> <version> [out_dir]
# Env:   DEVELOPER_ID_APPLICATION / DEVELOPER_ID_INSTALLER  (optional, same as build_distribution.sh)
# =============================================================================
set -euo pipefail

LITE_DMG="${1:?usage: $0 <Dotmini_MicroCode_Lite.dmg> <version> [out_dir]}"
VERSION="${2:?usage: $0 <Dotmini_MicroCode_Lite.dmg> <version> [out_dir]}"
OUT_DIR="${3:-Dist/AI}"

APP_NAME="MicroCode AI"
BUNDLE_ID="com.dotmini.microcode.ai"
VARIANT="Dotmini_MicroCode_AI_Universal"

[ -f "$LITE_DMG" ] || { echo "❌ Lite DMG not found: $LITE_DMG" >&2; exit 1; }

WORK="$(mktemp -d)"
MNT="$WORK/mnt"
STAGE="$WORK/stage"
mkdir -p "$MNT" "$STAGE" "$OUT_DIR"

cleanup() {
    hdiutil detach "$MNT" -quiet 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "📀 Mounting $(basename "$LITE_DMG")..."
hdiutil attach "$LITE_DMG" -mountpoint "$MNT" -nobrowse -readonly -quiet
SRC_APP="$(find "$MNT" -maxdepth 2 -name '*.app' -print -quit)"
[ -n "$SRC_APP" ] || { echo "❌ No .app inside $LITE_DMG" >&2; exit 1; }

APP="$STAGE/$APP_NAME.app"
ditto "$SRC_APP" "$APP"
hdiutil detach "$MNT" -quiet

PLIST="$APP/Contents/Info.plist"
set_plist() { # key type value
    /usr/libexec/PlistBuddy -c "Delete :$1" "$PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$PLIST"
}
set_plist CFBundleIdentifier string "$BUNDLE_ID"
set_plist CFBundleName string "$APP_NAME"
set_plist CFBundleDisplayName string "$APP_NAME"
set_plist CFBundleShortVersionString string "$VERSION"
set_plist MicroCodeStandaloneAI bool true

ENTITLEMENTS="$WORK/ai.entitlements"
cat > "$ENTITLEMENTS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.device.camera</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>
EOF

xattr -cr "$APP" 2>/dev/null || true
if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
    echo "🔐 Signing with Developer ID..."
    codesign --force --deep --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID_APPLICATION" "$APP"
else
    echo "🔐 Ad-hoc signing..."
    codesign --force --deep --entitlements "$ENTITLEMENTS" --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"

# The edition switch must be present, or the app would boot as the full IDE.
GOT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
GOT_FLAG="$(/usr/libexec/PlistBuddy -c 'Print :MicroCodeStandaloneAI' "$PLIST")"
[ "$GOT_ID" = "$BUNDLE_ID" ] && [ "$GOT_FLAG" = "true" ] || { echo "❌ Edition keys missing in Info.plist" >&2; exit 1; }

echo "💿 Creating DMG..."
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT_DIR/$VARIANT.dmg" "$OUT_DIR/$VARIANT.pkg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$OUT_DIR/$VARIANT.dmg" >/dev/null

echo "📦 Creating PKG..."
PKG_ARGS=(--component "$APP" --identifier "$BUNDLE_ID" --version "$VERSION" --install-location /Applications)
[ -n "${DEVELOPER_ID_INSTALLER:-}" ] && PKG_ARGS+=(--sign "$DEVELOPER_ID_INSTALLER")
pkgbuild "${PKG_ARGS[@]}" "$OUT_DIR/$VARIANT.pkg" >/dev/null

ls -lh "$OUT_DIR/$VARIANT".*
echo "✅ $APP_NAME $VERSION packaged from $(basename "$LITE_DMG")"
