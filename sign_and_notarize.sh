#!/bin/bash
# CodeTunner - Code Signing and Notarization Script
# For distributing to other users safely
#
# Requirements:
# 1. Apple Developer Account with Developer ID Application certificate
# 2. App-specific password for notarization (create at appleid.apple.com)
# 3. Xcode Command Line Tools installed
#
# Setup once:
# export DEVELOPER_ID="Developer ID Application: Your Name (TEAM_ID)"
# export APPLE_ID="your@email.com"
# export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx" # App-specific password
# export TEAM_ID="YOUR_TEAM_ID"

set -e

# Configuration
APP_NAME="CodeTunner"
BUNDLE_ID="com.dotmini.codetunner"
VERSION="${VERSION:-2.0.0 Developer}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${APP_PATH:-$SCRIPT_DIR/Dist/$APP_NAME.app}"
DMG_PATH="${DMG_PATH:-$SCRIPT_DIR/Dist/$APP_NAME-$VERSION.dmg}"
PKG_PATH="${PKG_PATH:-$SCRIPT_DIR/Dist/$APP_NAME-$VERSION.pkg}"
ENTITLEMENTS="$SCRIPT_DIR/entitlements.plist"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       CodeTunner - Signing & Notarization Tool            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check required environment variables
check_env() {
    if [ -z "$DEVELOPER_ID" ]; then
        echo -e "${RED}❌ DEVELOPER_ID not set${NC}"
        echo "   Set it with: export DEVELOPER_ID=\"Developer ID Application: Your Name (TEAM_ID)\""
        echo ""
        echo "   To find your Developer ID:"
        echo "   1. Open Keychain Access"
        echo "   2. Look for certificate starting with 'Developer ID Application:'"
        echo ""
        exit 1
    fi
    
    if [ -z "$APPLE_ID" ]; then
        echo -e "${RED}❌ APPLE_ID not set${NC}"
        echo "   Set it with: export APPLE_ID=\"your@email.com\""
        exit 1
    fi
    
    if [ -z "$APP_PASSWORD" ]; then
        echo -e "${RED}❌ APP_PASSWORD not set${NC}"
        echo "   Create an app-specific password at: https://appleid.apple.com"
        echo "   Account → App-Specific Passwords → Generate"
        echo "   Set it with: export APP_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\""
        exit 1
    fi
    
    if [ -z "$TEAM_ID" ]; then
        echo -e "${RED}❌ TEAM_ID not set${NC}"
        echo "   Find it at: https://developer.apple.com/account -> Membership -> Team ID"
        echo "   Set it with: export TEAM_ID=\"YOUR_TEAM_ID\""
        exit 1
    fi
    
    echo -e "${GREEN}✅ All credentials configured${NC}"
}

# Create entitlements file
create_entitlements() {
    echo -e "${YELLOW}📝 Creating entitlements...${NC}"
    
    cat > "$ENTITLEMENTS" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Hardened Runtime -->
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    
    <!-- Network Access -->
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    
    <!-- File Access -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>
    
    <!-- Device Access -->
    <key>com.apple.security.device.camera</key>
    <true/>
    <key>com.apple.security.device.usb</key>
    <true/>
    
    <!-- Process -->
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
EOF
    
    echo -e "${GREEN}✅ Entitlements created${NC}"
}

# Sign the app bundle
sign_app() {
    echo -e "${YELLOW}🔐 Signing app bundle...${NC}"
    
    # Sign all nested binaries and frameworks first
    echo "   Signing nested components..."
    
    # Sign helper tools
    find "$APP_PATH/Contents/MacOS" -type f -perm +111 | while read binary; do
        if [ "$binary" != "$APP_PATH/Contents/MacOS/$APP_NAME" ]; then
            echo "   Signing: $(basename "$binary")"
            codesign --force --options runtime \
                --entitlements "$ENTITLEMENTS" \
                --sign "$DEVELOPER_ID" \
                --timestamp \
                "$binary" 2>/dev/null || true
        fi
    done
    
    # Sign frameworks
    if [ -d "$APP_PATH/Contents/Frameworks" ]; then
        find "$APP_PATH/Contents/Frameworks" -name "*.framework" -or -name "*.dylib" | while read framework; do
            echo "   Signing: $(basename "$framework")"
            codesign --force --options runtime \
                --sign "$DEVELOPER_ID" \
                --timestamp \
                "$framework" 2>/dev/null || true
        done
    fi
    
    # Sign the main app bundle
    echo "   Signing main app..."
    codesign --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$DEVELOPER_ID" \
        --timestamp \
        "$APP_PATH"
    
    # Verify signature
    echo -e "${YELLOW}🔍 Verifying signature...${NC}"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    
    echo -e "${GREEN}✅ App signed successfully${NC}"
}

# Create DMG
create_dmg() {
    echo -e "${YELLOW}💿 Creating DMG...${NC}"
    
    # Remove old DMG
    rm -f "$DMG_PATH"
    
    # Create DMG
    create-dmg \
        --volname "$APP_NAME" \
        --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
        --background "$SCRIPT_DIR/resources/dmg-background.png" 2>/dev/null || \
    create-dmg \
        --volname "$APP_NAME" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$(basename "$APP_PATH")" 150 190 \
        --app-drop-link 450 190 \
        "$DMG_PATH" \
        "$APP_PATH" 2>/dev/null || \
    hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"
    
    # Sign DMG
    codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"
    
    echo -e "${GREEN}✅ DMG created and signed${NC}"
}

# Create signed PKG
create_pkg() {
    echo -e "${YELLOW}📦 Creating installer package...${NC}"
    
    # Remove old PKG
    rm -f "$PKG_PATH"
    
    # Create component package
    pkgbuild --root "$APP_PATH" \
        --component-plist /dev/stdin \
        --identifier "$BUNDLE_ID" \
        --version "$VERSION" \
        --install-location "/Applications/$APP_NAME.app" \
        --sign "$DEVELOPER_ID" \
        "$SCRIPT_DIR/Dist/component.pkg" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
    <dict>
        <key>BundleHasStrictIdentifier</key>
        <true/>
        <key>BundleIsRelocatable</key>
        <false/>
        <key>BundleIsVersionChecked</key>
        <true/>
        <key>BundleOverwriteAction</key>
        <string>upgrade</string>
    </dict>
</array>
</plist>
EOF
    
    # Create distribution package
    productbuild --distribution "$SCRIPT_DIR/distribution.xml" \
        --package-path "$SCRIPT_DIR/Dist" \
        --sign "Developer ID Installer: $(echo $DEVELOPER_ID | sed 's/Developer ID Application://')" \
        "$PKG_PATH" 2>/dev/null || \
    productbuild --component "$APP_PATH" /Applications \
        --sign "Developer ID Installer: $(echo $DEVELOPER_ID | sed 's/Developer ID Application://')" \
        "$PKG_PATH" 2>/dev/null || \
    mv "$SCRIPT_DIR/Dist/component.pkg" "$PKG_PATH"
    
    echo -e "${GREEN}✅ Installer package created${NC}"
}

# Notarize the app
notarize_app() {
    echo -e "${YELLOW}📤 Submitting for notarization...${NC}"
    echo "   This may take several minutes..."
    
    # Submit for notarization
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait
    
    # Check result
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Notarization successful${NC}"
        
        # Staple the notarization ticket
        echo -e "${YELLOW}📌 Stapling ticket...${NC}"
        xcrun stapler staple "$DMG_PATH"
        xcrun stapler staple "$APP_PATH"
        
        echo -e "${GREEN}✅ Stapling complete${NC}"
    else
        echo -e "${RED}❌ Notarization failed${NC}"
        echo "   Check the log with: xcrun notarytool log <submission-id> --apple-id \"$APPLE_ID\" --password \"$APP_PASSWORD\" --team-id \"$TEAM_ID\""
        exit 1
    fi
}

# Verify everything
verify_distribution() {
    echo -e "${YELLOW}🔍 Verifying distribution...${NC}"
    
    # Check signature
    echo "   Checking code signature..."
    codesign -dv --verbose=4 "$APP_PATH" 2>&1 | head -20
    
    # Check notarization
    echo ""
    echo "   Checking notarization..."
    spctl -a -vv "$APP_PATH" 2>&1
    
    # Check DMG
    echo ""
    echo "   Checking DMG..."
    spctl -a -t open --context context:primary-signature -v "$DMG_PATH" 2>&1
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ Distribution package ready!${NC}"
    echo ""
    echo -e "📁 Files:"
    echo -e "   ${BLUE}$DMG_PATH${NC}"
    ls -lh "$DMG_PATH" 2>/dev/null
    echo ""
    echo -e "   ${BLUE}$PKG_PATH${NC}"
    ls -lh "$PKG_PATH" 2>/dev/null
    echo ""
    echo -e "${GREEN}These files can now be safely distributed to other users!${NC}"
}

# Main
main() {
    case "${1:-all}" in
        check)
            check_env
            ;;
        sign)
            check_env
            create_entitlements
            sign_app
            ;;
        dmg)
            check_env
            create_dmg
            ;;
        pkg)
            check_env
            create_pkg
            ;;
        notarize)
            check_env
            notarize_app
            ;;
        verify)
            verify_distribution
            ;;
        all)
            check_env
            create_entitlements
            sign_app
            create_dmg
            create_pkg
            notarize_app
            verify_distribution
            ;;
        help|*)
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  check     - Check if credentials are configured"
            echo "  sign      - Sign the app bundle"
            echo "  dmg       - Create signed DMG"
            echo "  pkg       - Create signed PKG"
            echo "  notarize  - Submit for notarization"
            echo "  verify    - Verify distribution"
            echo "  all       - Do everything (default)"
            echo ""
            echo "Environment variables required:"
            echo "  DEVELOPER_ID  - Your Developer ID certificate name"
            echo "  APPLE_ID      - Your Apple ID email"
            echo "  APP_PASSWORD  - App-specific password"
            echo "  TEAM_ID       - Your Apple Developer Team ID"
            ;;
    esac
}

main "$@"
