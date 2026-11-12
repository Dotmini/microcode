#!/bin/bash
set -e

# Parse arguments
BUNDLE_RUNTIMES=false
BUNDLE_SECRETS=false
SWIFT_CONFIG="debug"
SWIFT_PRODUCT_DIR="Debug"
while [[ $# -gt 0 ]]; do
    case $1 in
        --release)
            SWIFT_CONFIG="release"
            SWIFT_PRODUCT_DIR="Release"
            shift
            ;;
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
            echo "Usage: ./build_dev.sh [--release] [--with-runtimes] [--with-secrets]"
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

# Collect potential Rust library directories (prefer release first when --release is active)
RUST_LINK_FLAGS=()
if [ "$SWIFT_CONFIG" = "release" ]; then
    CANDIDATE_RUST_DIRS=(
        "$BUILD_ROOT/cargo-target/release"
        ".codetuner-build/cargo-target/release"
        "/Volumes/MicroCodeBuild/cargo-target/release"
        "/Volumes/MAC/CodeTunerBuild/cargo-target/release"
        "${CODETUNER_BUILD_ROOT:-}/cargo-target/release"
        "backend/target/release"
        "microcode_core/target/release"
        "microcode_core/target/aarch64-apple-darwin/release"
        "$BUILD_ROOT/cargo-target/debug"
        ".codetuner-build/cargo-target/debug"
        "MicrocodeCoreSupport"
    )
else
    CANDIDATE_RUST_DIRS=(
        "$BUILD_ROOT/cargo-target/debug"
        "$BUILD_ROOT/cargo-target/release"
        ".codetuner-build/cargo-target/debug"
        ".codetuner-build/cargo-target/release"
        "/Volumes/MAC/CodeTunerBuild/cargo-target/debug"
        "/Volumes/MAC/CodeTunerBuild/cargo-target/release"
        "/Volumes/MicroCodeBuild/cargo-target/release"
        "/Volumes/MicroCodeBuild/cargo-target/debug"
        "${CODETUNER_BUILD_ROOT:-}/cargo-target/release"
        "${CODETUNER_BUILD_ROOT:-}/cargo-target/debug"
        "backend/target/debug"
        "backend/target/release"
        ".build/cargo-target/debug"
        ".build/cargo-target/release"
        "build/cargo-target/debug"
        "build/cargo-target/release"
        "microcode_core/target/release"
        "microcode_core/target/debug"
        "microcode_core/target/aarch64-apple-darwin/release"
        "MicrocodeCoreSupport"
    )
fi
for libdir in "${CANDIDATE_RUST_DIRS[@]}"; do
    if [ -n "$libdir" ] && [ -d "$libdir" ]; then
        RUST_LINK_FLAGS+=("-Xlinker" "-L$libdir")
    fi
done

BUILD_START_MARKER="$BUILD_ROOT/tmp/.build_start_marker"
touch "$BUILD_START_MARKER"

SWIFT_RELEASE_FLAGS=()
if [ "$SWIFT_CONFIG" = "release" ]; then
    # Compile every file with full -O LLVM optimization in bounded per-batch jobs (-j 4)
    # so monolithic 340-file WMO never exhausts macOS VM swap space on constrained disks.
    SWIFT_RELEASE_FLAGS+=("-j" "4" "-Xswiftc" "-no-whole-module-optimization")
fi

if ! swift build -c "$SWIFT_CONFIG" --scratch-path "$SWIFT_SCRATCH_PATH" \
    "${SWIFT_RELEASE_FLAGS[@]}" \
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
    if [ -f "$SWIFT_SCRATCH_PATH/out/Products/$SWIFT_PRODUCT_DIR/MicroCode" ] && [ "$SWIFT_SCRATCH_PATH/out/Products/$SWIFT_PRODUCT_DIR/MicroCode" -nt "$BUILD_START_MARKER" ]; then
        echo "ℹ️  Swift linker produced fresh $SWIFT_SCRATCH_PATH/out/Products/$SWIFT_PRODUCT_DIR/MicroCode (ignoring ExFAT codesign warning during scratch build; final bundle will be signed on APFS)"
    else
        echo "❌ Swift build failed to produce a fresh binary."
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
FINAL_BUNDLE_NAME="${CODETUNER_APP_DEST:-$DEFAULT_APP_DIR/MicroCode.app}"
BUNDLE_PARENT_DIR="$(dirname "$FINAL_BUNDLE_NAME")"
BUNDLE_BASE_NAME="$(basename "$FINAL_BUNDLE_NAME")"
BUNDLE_NAME="$BUNDLE_PARENT_DIR/.staging_${BUNDLE_BASE_NAME}"
rm -rf "$BUNDLE_NAME"
echo "📦 Staging Bundle: $FINAL_BUNDLE_NAME"
mkdir -p "$BUNDLE_NAME/Contents/MacOS"
mkdir -p "$BUNDLE_NAME/Contents/Resources"

# 3. Copy Binary
BINARY_PATH="$SWIFT_SCRATCH_PATH/out/Products/$SWIFT_PRODUCT_DIR/MicroCode"
if [ ! -f "$BINARY_PATH" ]; then
    BINARY_PATH="$(swift build -c "$SWIFT_CONFIG" --scratch-path "$SWIFT_SCRATCH_PATH" --show-bin-path)/MicroCode"
fi
if [ ! -f "$BINARY_PATH" ]; then
    BINARY_PATH=$(find "$SWIFT_SCRATCH_PATH" -name "MicroCode" -type f ! -path "*.dSYM*" 2>/dev/null | head -n 1)
fi
if [ ! -f "$BINARY_PATH" ]; then
    echo "Critical Error: Could not locate compiled binary in $SWIFT_SCRATCH_PATH."
    exit 1
fi
echo "Using binary at: $BINARY_PATH"

# Use local APFS /tmp for post-build strip/install_name_tool/codesign so a full external scratch volume never truncates the binary
export TMPDIR="/tmp"
DEST_BIN="$BUNDLE_NAME/Contents/MacOS/MicroCode"
cp -f "$BINARY_PATH" "$DEST_BIN"
chmod +x "$DEST_BIN"
if strip -x "$DEST_BIN" 2>/dev/null; then
    :
fi
if [ ! -s "$DEST_BIN" ]; then
    # Fallback if strip failed due to temp space
    cp -f "$BINARY_PATH" "$DEST_BIN"
    chmod +x "$DEST_BIN"
fi
install_name_tool -change /Volumes/MAC/CodeTunerBuild/cargo-target/debug/deps/libmicrocode_core.dylib @rpath/libmicrocode_core.dylib "$DEST_BIN" 2>/dev/null || true
install_name_tool -change /Users/dotmini/Documents/SX/codetunner-native/microcode_core/target/release/deps/libmicrocode_core.dylib @rpath/libmicrocode_core.dylib "$DEST_BIN" 2>/dev/null || true
install_name_tool -change /Volumes/MAC/CodeTunerBuild/cargo-target/debug/deps/libmicrocode_embedded.dylib @rpath/libmicrocode_embedded.dylib "$DEST_BIN" 2>/dev/null || true
install_name_tool -add_rpath @executable_path/../Frameworks "$DEST_BIN" 2>/dev/null || true

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
    <string>2.5.41</string>
    <key>CFBundleVersion</key>
    <string>38</string>
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
    <string>MicroCode uses your microphone for voice commands and live audio preview.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>MicroCode uses on-device Speech Recognition to transcribe your voice commands directly into AI Agent prompts.</string>
    <key>NSCameraUseContinuityCameraDeviceType</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>MicroCode discovers and connects to Local LLM servers (LM Studio, Ollama, Apple MLX, vLLM, macLLM, and MicroCode peers) across your Wi-Fi and LAN network.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>MicroCode uses Apple Events to automate developer tools, terminals, simulators, and browsers when requested by the user or AI Agent.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>MicroCode accesses your Documents folder to open, edit, build, and run your code workspaces.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>MicroCode accesses your Desktop folder when opening or saving project files.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>MicroCode accesses your Downloads folder when importing models or project files.</string>
    <key>NSNetworkVolumesUsageDescription</key>
    <string>MicroCode accesses network volumes when working with remote project workspaces.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>MicroCode accesses external drives when building projects or loading local LLM models.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>MicroCode uses Bluetooth for nearby device discovery and companion pairing.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_microcode-llm._tcp</string>
        <string>_microcode-phone._tcp</string>
        <string>_ollama._tcp</string>
        <string>_http._tcp</string>
        <string>_smb._tcp</string>
        <string>_ssh._tcp</string>
        <string>_workstation._tcp</string>
        <string>_rfb._tcp</string>
        <string>_companion-link._tcp</string>
    </array>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.dotmini.microcode</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>microcode</string>
                <string>microcode-file</string>
            </array>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>MicroCode Portable Agent Capsule</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>CFBundleTypeIconFile</key>
            <string>AppIcon</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.dotmini.microcode.arx</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>arx</string>
            </array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.dotmini.microcode.arx</string>
            <key>UTTypeDescription</key>
            <string>MicroCode Portable Agent Capsule (.arx)</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>arx</string>
                </array>
            </dict>
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
if [ -d "tools" ]; then
    mkdir -p "$BUNDLE_NAME/Contents/Resources/tools"
    cp -R "tools/." "$BUNDLE_NAME/Contents/Resources/tools/"
fi
if [ -d "MicroCode/Resources" ]; then
    echo "   Copying MicroCode/Resources into Bundle Resources..."
    cp -R MicroCode/Resources/* "$BUNDLE_NAME/Contents/Resources/"
fi
if [ -d "Extensions" ]; then
    mkdir -p "$BUNDLE_NAME/Contents/Resources/Extensions"
    cp -R "Extensions/." "$BUNDLE_NAME/Contents/Resources/Extensions/"
fi
if [ -f "vscode-compat-host/dist/index.js" ] && [ -f "vscode-compat-host/dist/api.js" ]; then
    mkdir -p "$BUNDLE_NAME/Contents/Resources/vscode-compat"
    cp "vscode-compat-host/dist/index.js" "$BUNDLE_NAME/Contents/Resources/vscode-compat/index.js"
    cp "vscode-compat-host/dist/api.js" "$BUNDLE_NAME/Contents/Resources/vscode-compat/api.js"
fi
if [ -d "Vendor/serve-sim/0.1.46" ]; then
    echo "   Bundling Fast iOS Preview runtime (serve-sim 0.1.46)..."
    SERVE_SIM_SOURCE="Vendor/serve-sim/0.1.46"
    SERVE_SIM_DEST="$BUNDLE_NAME/Contents/Resources/serve-sim"
    mkdir -p "$SERVE_SIM_DEST/node_modules"
    cp -R "$SERVE_SIM_SOURCE/dist" "$SERVE_SIM_DEST/dist"
    cp "$SERVE_SIM_SOURCE/package.json" "$SERVE_SIM_DEST/package.json"
    if [ -d "$SERVE_SIM_SOURCE/bin" ]; then
        cp -R "$SERVE_SIM_SOURCE/bin" "$SERVE_SIM_DEST/bin"
    fi
    if [ -d "$SERVE_SIM_SOURCE/node_modules/ws" ]; then
        cp -R "$SERVE_SIM_SOURCE/node_modules/ws" "$SERVE_SIM_DEST/node_modules/ws"
    fi
    chmod +x "$SERVE_SIM_DEST/dist/serve-sim.js" 2>/dev/null || true
    chmod +x "$SERVE_SIM_DEST/bin/xcrun" 2>/dev/null || true
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
    install_name_tool -id @rpath/libmicrocode_core.dylib "$BUNDLE_NAME/Contents/Frameworks/libmicrocode_core.dylib" 2>/dev/null || true
fi
for emb_dylib in \
    "$BUILD_ROOT/cargo-target/$SWIFT_CONFIG/libmicrocode_embedded.dylib" \
    ".codetuner-build/cargo-target/$SWIFT_CONFIG/libmicrocode_embedded.dylib" \
    ".codetuner-build/cargo-target/release/libmicrocode_embedded.dylib" \
    "$BUILD_ROOT/cargo-target/debug/libmicrocode_embedded.dylib"
do
    if [ -f "$emb_dylib" ]; then
        echo "   Copying $emb_dylib into Frameworks..."
        cp "$emb_dylib" "$BUNDLE_NAME/Contents/Frameworks/libmicrocode_embedded.dylib"
        install_name_tool -id @rpath/libmicrocode_embedded.dylib "$BUNDLE_NAME/Contents/Frameworks/libmicrocode_embedded.dylib" 2>/dev/null || true
        break
    fi
done

# 7. Code Sign Staging Bundle, then Atomically Swap into Final Destination
echo "🔐 Signing Bundle..."
dot_clean -m "$BUNDLE_NAME" 2>/dev/null || true
xattr -cr "$BUNDLE_NAME" 2>/dev/null || true
if security find-identity -v -p codesigning | grep -q "Apple Development: business@dotmini.net (A58QB9B355)"; then
    codesign --force --deep --sign "Apple Development: business@dotmini.net (A58QB9B355)" "$BUNDLE_NAME" 2>/dev/null || codesign --force --deep --sign - "$BUNDLE_NAME"
else
    codesign --force --deep --sign - "$BUNDLE_NAME"
fi

if pgrep -f "$FINAL_BUNDLE_NAME/Contents/MacOS/MicroCode" >/dev/null 2>&1; then
    echo "⏹ Stopping running MicroCode instance at $FINAL_BUNDLE_NAME..."
    pkill -TERM -f "$FINAL_BUNDLE_NAME/Contents/MacOS/MicroCode" 2>/dev/null || true
    sleep 0.4
    pkill -KILL -f "$FINAL_BUNDLE_NAME/Contents/MacOS/MicroCode" 2>/dev/null || true
fi
rm -rf "$FINAL_BUNDLE_NAME"
mv "$BUNDLE_NAME" "$FINAL_BUNDLE_NAME"
BUNDLE_NAME="$FINAL_BUNDLE_NAME"

# Show final size
echo ""
echo "📊 Dev Bundle Size: $(du -sh "$BUNDLE_NAME" | cut -f1)"
echo "✅ Dev Bundle Ready: $BUNDLE_NAME"

if [ -z "${CODETUNER_APP_DEST:-}" ] || [ "$BUNDLE_NAME" = "/Applications/MicroCode.app" ]; then
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
            codesign --force --deep --sign "Apple Development: business@dotmini.net (A58QB9B355)" "/Applications/MicroCode.app" 2>/dev/null || codesign --force --deep --sign - "/Applications/MicroCode.app"
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
else
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$BUNDLE_NAME" 2>/dev/null || true
    echo "📱 Custom Application Bundle registered: $BUNDLE_NAME (main /Applications/MicroCode.app untouched)"
fi
