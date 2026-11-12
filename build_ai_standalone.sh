#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🤖 Building MicroCode AI (Standalone Agent + Settings Edition)..."

# 1. Build the core binary / bundle into /Applications/MicroCode AI.app (never touching /Applications/MicroCode.app)
CODETUNER_APP_DEST="/Applications/MicroCode AI.app" ./build_dev.sh "$@"

STANDALONE_APP="/Applications/MicroCode AI.app"
PLIST="$STANDALONE_APP/Contents/Info.plist"

# 2. Copy microcode-backend into Standalone bundle if available
if [ ! -f "$STANDALONE_APP/Contents/MacOS/microcode-backend" ]; then
    for candidate_backend in \
        "/Applications/MicroCode.app/Contents/MacOS/microcode-backend" \
        "backend/target/release/microcode-backend" \
        ".codetuner-build/cargo-target/release/microcode-backend" \
        "/Volumes/MAC/CodeTunerBuild/cargo-target/release/microcode-backend" \
        "/Volumes/MAC/CodeTunerBuild/cargo-target/debug/microcode-backend"
    do
        if [ -f "$candidate_backend" ]; then
            cp -f "$candidate_backend" "$STANDALONE_APP/Contents/MacOS/microcode-backend"
            chmod +x "$STANDALONE_APP/Contents/MacOS/microcode-backend"
            break
        fi
    done
fi

# 3. Customize Info.plist for Standalone MicroCode AI
if [ -f "$PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.dotmini.microcode.ai" "$PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleName 'MicroCode AI'" "$PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 'MicroCode AI'" "$PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :MicroCodeStandaloneAI" "$PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :MicroCodeStandaloneAI bool true" "$PLIST" 2>/dev/null || true
fi

# 4. Re-sign bundle on APFS after Info.plist customization
ENTITLEMENTS_TMP="/tmp/microcode_ai_standalone.entitlements"
cat > "$ENTITLEMENTS_TMP" <<EOF
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

xattr -cr "$STANDALONE_APP" 2>/dev/null || true
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS_TMP" "$STANDALONE_APP"
rm -f "$ENTITLEMENTS_TMP"

echo "✅ Standalone MicroCode AI built at: $STANDALONE_APP"
