#!/bin/bash
set -e

# Parse arguments
BUNDLE_RUNTIMES=false
BUNDLE_SECRETS=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --with-runtimes)
            BUNDLE_RUNTIMES=true
            shift
            ;;
        --with-secrets)
            # Opt-in only: embeds local Secrets.plist (API keys) into the .app.
            # Never distribute a bundle built with this flag.
            BUNDLE_SECRETS=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: ./build_dev.sh [--with-runtimes] [--with-secrets]"
            exit 1
            ;;
    esac
done

# 1. Build Swift (using External SSD when available)
echo "🏗️ Building Swift frontend..."
if [ -n "${CODETUNER_BUILD_ROOT:-}" ]; then
    BUILD_ROOT="$CODETUNER_BUILD_ROOT"
elif [ -d "/Volumes/MicroCodeBuild" ]; then
    BUILD_ROOT="/Volumes/MicroCodeBuild"
elif [ -d "/Volumes/XcodeWork" ]; then
    BUILD_ROOT="/Volumes/XcodeWork/MicroCodeBuild"
elif [ -d "/Volumes/MAC" ]; then
    BUILD_ROOT="/Volumes/MAC/CodeTunerBuild"
else
    BUILD_ROOT="$(pwd)/.codetuner-build"
fi

echo "ℹ Build Root: $BUILD_ROOT"
mkdir -p "$BUILD_ROOT/cargo-home" "$BUILD_ROOT/cargo-target" "$BUILD_ROOT/swiftpm" "$BUILD_ROOT/tmp" "$BUILD_ROOT/apps"
# Clean stale temp files and redundant external .app copies to prevent external SSD disk-full errors during codesign
rm -rf "$BUILD_ROOT/tmp/"* "$BUILD_ROOT/apps/MicroCode.app" 2>/dev/null || true
export TMPDIR="$BUILD_ROOT/tmp"
export CARGO_HOME="$BUILD_ROOT/cargo-home"
export CARGO_TARGET_DIR="$BUILD_ROOT/cargo-target"
SWIFT_SCRATCH_PATH="$BUILD_ROOT/swiftpm/$(basename "$PWD")"

# Collect potential Rust library directories
RUST_LINK_FLAGS=()
for libdir in \
    "$BUILD_ROOT/cargo-target/debug" \
    "$BUILD_ROOT/cargo-target/release" \
    "/Volumes/MAC/CodeTunerBuild/cargo-target/debug" \
    "/Volumes/MAC/CodeTunerBuild/cargo-target/release" \
    "/Volumes/MicroCodeBuild/cargo-target/release" \
    "/Volumes/MicroCodeBuild/cargo-target/debug" \
    "${CODETUNER_BUILD_ROOT:-}/cargo-target/release" \
    "${CODETUNER_BUILD_ROOT:-}/cargo-target/debug" \
    "backend/target/debug" \
    "backend/target/release" \
    ".build/cargo-target/debug" \
    ".build/cargo-target/release" \
    "build/cargo-target/debug" \
    "build/cargo-target/release" \
    "microcode_core/target/release" \
    "microcode_core/target/debug" \
    "microcode_core/target/aarch64-apple-darwin/release" \
    "MicrocodeCoreSupport"
do
    if [ -n "$libdir" ] && [ -d "$libdir" ]; then
        RUST_LINK_FLAGS+=("-Xlinker" "-L$libdir")
    fi
done

BUILD_START_MARKER="$BUILD_ROOT/tmp/.build_start_marker"
touch "$BUILD_START_MARKER"

if ! swift build -c debug --scratch-path "$SWIFT_SCRATCH_PATH" \
    "${RUST_LINK_FLAGS[@]}" \
    -Xlinker -lmicrocode_embedded \
    -Xlinker -lmicrocode_core \
    -Xlinker -lbz2 \
    -Xlinker -llzma \
    -Xlinker -lz \
    -Xlinker -liconv \
    -Xlinker -framework -Xlinker Virtualization \
    -Xlinker -framework -Xlinker SystemConfiguration \
    -Xlinker -framework -Xlinker Security \
    -Xlinker -framework -Xlinker CoreFoundation \
    -Xlinker -headerpad_max_install_names; then
    if [ -f "$SWIFT_SCRATCH_PATH/out/Products/Debug/MicroCode" ]; then
        echo "ℹ️  Swift linker produced $SWIFT_SCRATCH_PATH/out/Products/Debug/MicroCode (ignoring ExFAT codesign warning during scratch build; final bundle will be signed on APFS)"
    else
        echo "❌ Swift build failed to produce binary."
        exit 1
    fi
fi

# 2. Create Bundle directly in /Applications (APFS) so external scratch SSD never runs out of space
if [ -w "/Applications" ]; then
    DEFAULT_APP_DIR="/Applications"
else
    DEFAULT_APP_DIR="$BUILD_ROOT/apps"
fi
mkdir -p "$DEFAULT_APP_DIR"
BUNDLE_NAME="${CODETUNER_APP_DEST:-$DEFAULT_APP_DIR/MicroCode.app}"
# Gracefully terminate any running instance executing from $BUNDLE_NAME BEFORE unlinking
# its Mach-O binary on external storage (prevents mmap __TEXT page-fault SIGBUS loops).
if pgrep -f "$BUNDLE_NAME/Contents/MacOS/MicroCode" >/dev/null 2>&1; then
    echo "⏹ Stopping running MicroCode instance at $BUNDLE_NAME..."
    pkill -TERM -f "$BUNDLE_NAME/Contents/MacOS/MicroCode" 2>/dev/null || true
    sleep 0.5
    pkill -KILL -f "$BUNDLE_NAME/Contents/MacOS/MicroCode" 2>/dev/null || true
fi
rm -rf "$BUNDLE_NAME"
echo "📦 Creating Bundle: $BUNDLE_NAME"
mkdir -p "$BUNDLE_NAME/Contents/MacOS"
mkdir -p "$BUNDLE_NAME/Contents/Resources"

# 3. Copy Binary
BINARY_PATH="$SWIFT_SCRATCH_PATH/out/Products/Debug/MicroCode"
if [ ! -f "$BINARY_PATH" ]; then
    BINARY_PATH="$(swift build -c debug --scratch-path "$SWIFT_SCRATCH_PATH" --show-bin-path)/MicroCode"
fi
if [ ! -f "$BINARY_PATH" ]; then
    BINARY_PATH=$(find "$SWIFT_SCRATCH_PATH" -name "MicroCode" -type f ! -path "*.dSYM*" 2>/dev/null | head -n 1)
fi
if [ ! -f "$BINARY_PATH" ]; then
    echo "Critical Error: Could not locate compiled binary in $SWIFT_SCRATCH_PATH."
    exit 1
fi
echo "Using binary at: $BINARY_PATH"

cp "$BINARY_PATH" "$BUNDLE_NAME/Contents/MacOS/"

# 4. Create Info.plist
cat > "$BUNDLE_NAME/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MicroCode</string>
    <key>CFBundleIdentifier</key>
    <string>com.dotmini.microcode</string>
    <key>CFBundleName</key>
    <string>MicroCode</string>
    <key>CFBundleDisplayName</key>
    <string>MicroCode</string>
    <key>CFBundleShortVersionString</key>
    <string>2.5.32</string>
    <key>CFBundleVersion</key>
    <string>32</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>MicroCode captures only the Apple Device Hub window you select to display an interactive iOS Simulator beside your chat.</string>
    <key>NSCameraUsageDescription</key>
    <string>MicroCode requires camera and video input access to preview and mirror physical iOS devices (iPhone and iPad) connected via USB.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>MicroCode requires microphone access for audio preview.</string>
    <key>NSCameraUseContinuityCameraDeviceType</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.dotmini.microcode</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>microcode</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# 5. Resources (Logo, etc)
if [ -f "AppIcon.icns" ]; then
    echo "   Copying AppIcon.icns..."
    cp "AppIcon.icns" "$BUNDLE_NAME/Contents/Resources/AppIcon.icns"
elif [ -f "microcodexround.icns" ]; then
    echo "   Copying microcodexround.icns as AppIcon.icns..."
    cp "microcodexround.icns" "$BUNDLE_NAME/Contents/Resources/AppIcon.icns"
fi
if [ -f "MicroCOdeDoogleIcon.png" ]; then
    echo "   Copying logo..."
    cp "MicroCOdeDoogleIcon.png" "$BUNDLE_NAME/Contents/Resources/"
fi
if [ "$BUNDLE_SECRETS" = true ] && [ -f "Secrets.plist" ]; then
    echo "   ⚠️  Copying Secrets.plist (--with-secrets): do NOT distribute this bundle"
    cp "Secrets.plist" "$BUNDLE_NAME/Contents/Resources/"
fi
if [ -f "mcp-server.py" ]; then
    echo "   Copying mcp-server.py into Bundle Resources..."
    cp "mcp-server.py" "$BUNDLE_NAME/Contents/Resources/"
    chmod +x "$BUNDLE_NAME/Contents/Resources/mcp-server.py"
fi
if [ -d "MicroCode/Resources" ]; then
    echo "   Copying MicroCode/Resources into Bundle Resources..."
    cp -R MicroCode/Resources/* "$BUNDLE_NAME/Contents/Resources/"
fi

# 6. Bundle Runtimes (only if --with-runtimes flag is passed)
if [ "$BUNDLE_RUNTIMES" = true ]; then
    echo "🔧 Bundling Runtimes..."
    ./bundle_runtimes.sh "$BUNDLE_NAME" "arm64"
else
    echo "⏭️  Skipping runtime bundling (use --with-runtimes to include)"
    echo "   Dev build will use system-installed Node.js/Go/Python via PATH"
fi

# 6.5 Frameworks & Dynamic Libraries
mkdir -p "$BUNDLE_NAME/Contents/Frameworks"
if [ -f "MicrocodeCoreSupport/libmicrocode_core.dylib" ]; then
    echo "   Copying libmicrocode_core.dylib into Frameworks..."
    cp "MicrocodeCoreSupport/libmicrocode_core.dylib" "$BUNDLE_NAME/Contents/Frameworks/"
    install_name_tool -change /Volumes/MAC/CodeTunerBuild/cargo-target/debug/deps/libmicrocode_core.dylib @rpath/libmicrocode_core.dylib "$BUNDLE_NAME/Contents/MacOS/MicroCode" 2>/dev/null || true
    install_name_tool -change /Users/dotmini/Documents/SX/codetunner-native/microcode_core/target/release/deps/libmicrocode_core.dylib @rpath/libmicrocode_core.dylib "$BUNDLE_NAME/Contents/MacOS/MicroCode" 2>/dev/null || true
    install_name_tool -add_rpath @executable_path/../Frameworks "$BUNDLE_NAME/Contents/MacOS/MicroCode" 2>/dev/null || true
fi
if [ -f "$BUILD_ROOT/cargo-target/debug/libmicrocode_embedded.dylib" ]; then
    echo "   Copying libmicrocode_embedded.dylib into Frameworks..."
    cp "$BUILD_ROOT/cargo-target/debug/libmicrocode_embedded.dylib" "$BUNDLE_NAME/Contents/Frameworks/"
    install_name_tool -id @rpath/libmicrocode_embedded.dylib "$BUNDLE_NAME/Contents/Frameworks/libmicrocode_embedded.dylib" 2>/dev/null || true
    install_name_tool -change /Volumes/MAC/CodeTunerBuild/cargo-target/debug/deps/libmicrocode_embedded.dylib @rpath/libmicrocode_embedded.dylib "$BUNDLE_NAME/Contents/MacOS/MicroCode" 2>/dev/null || true
    install_name_tool -add_rpath @executable_path/../Frameworks "$BUNDLE_NAME/Contents/MacOS/MicroCode" 2>/dev/null || true
fi

# 7. Strip Debug Symbols & Code Sign Bundle
strip -x "$BUNDLE_NAME/Contents/MacOS/MicroCode" 2>/dev/null || true
echo "🔐 Signing Bundle..."
dot_clean -m "$BUNDLE_NAME" 2>/dev/null || true
xattr -cr "$BUNDLE_NAME" 2>/dev/null || true
if security find-identity -v -p codesigning | grep -q "Apple Development: business@dotmini.net (A58QB9B355)"; then
    codesign --force --deep --sign "Apple Development: business@dotmini.net (A58QB9B355)" "$BUNDLE_NAME" 2>/dev/null || true
else
    codesign --force --deep --sign - "$BUNDLE_NAME" 2>/dev/null || true
fi

# Show final size
echo ""
echo "📊 Dev Bundle Size: $(du -sh "$BUNDLE_NAME" | cut -f1)"
echo "✅ Dev Bundle Ready: $BUNDLE_NAME"

# Symlink to root workspace so standard open / shortcuts work with 0 disk overhead on internal drive
rm -rf "MicroCode.app"
ln -sfn "$BUNDLE_NAME" "MicroCode.app"
echo "🔗 Workspace symlink updated: MicroCode.app -> $BUNDLE_NAME"

# Register with LaunchServices if installed in /Applications
if [ "$BUNDLE_NAME" = "/Applications/MicroCode.app" ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/MicroCode.app" 2>/dev/null || true
    echo "📱 System Applications updated (real bundle): /Applications/MicroCode.app"
elif [ -w "/Applications" ]; then
    rm -rf "/Applications/MicroCode.app"
    ditto "$BUNDLE_NAME" "/Applications/MicroCode.app"
    dot_clean -m "/Applications/MicroCode.app" 2>/dev/null || true
    xattr -cr "/Applications/MicroCode.app" 2>/dev/null || true
    if security find-identity -v -p codesigning | grep -q "Apple Development: business@dotmini.net (A58QB9B355)"; then
        codesign --force --deep --sign "Apple Development: business@dotmini.net (A58QB9B355)" "/Applications/MicroCode.app"
    else
        codesign --force --deep --sign - "/Applications/MicroCode.app"
    fi
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/MicroCode.app" 2>/dev/null || true
    echo "📱 System Applications updated (real bundle): /Applications/MicroCode.app"
fi

# Also sync to ~/Applications folder so Dock/Spotlight shortcuts pointing there never run a stale build
if [ -d "$HOME/Applications" ]; then
    rm -rf "$HOME/Applications/MicroCode.app"
    ln -sfn "/Applications/MicroCode.app" "$HOME/Applications/MicroCode.app"
    echo "📱 User Applications updated: $HOME/Applications/MicroCode.app -> /Applications/MicroCode.app"
fi
