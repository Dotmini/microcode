#!/bin/bash
set -e

# Parse arguments
BUNDLE_RUNTIMES=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --with-runtimes)
            BUNDLE_RUNTIMES=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: ./build_dev.sh [--with-runtimes]"
            exit 1
            ;;
    esac
done

# 1. Build Swift (assuming Rust is built or handled separately/before)
echo "🏗️ Building Swift frontend..."
export TMPDIR="${TMPDIR:-/tmp}"
mkdir -p "$TMPDIR"

# Collect potential Rust library directories
RUST_LINK_FLAGS=()
for libdir in \
    "backend/target/debug" \
    "backend/target/release" \
    ".build/cargo-target/debug" \
    ".build/cargo-target/release" \
    "build/cargo-target/debug" \
    "build/cargo-target/release" \
    "${CODETUNER_BUILD_ROOT:-}/cargo-target/release" \
    "${CODETUNER_BUILD_ROOT:-}/cargo-target/debug" \
    "/Volumes/MicroCodeBuild/cargo-target/release" \
    "/Volumes/MicroCodeBuild/cargo-target/debug" \
    "microcode_core/target/release" \
    "microcode_core/target/debug" \
    "microcode_core/target/aarch64-apple-darwin/release" \
    "MicrocodeCoreSupport"
do
    if [ -n "$libdir" ] && [ -d "$libdir" ]; then
        RUST_LINK_FLAGS+=("-Xlinker" "-L$libdir")
    fi
done

swift build -c debug \
    "${RUST_LINK_FLAGS[@]}" \
    -Xlinker -lmicrocode_embedded \
    -Xlinker -lmicrocode_core \
    -Xlinker -framework -Xlinker SystemConfiguration \
    -Xlinker -framework -Xlinker Security \
    -Xlinker -framework -Xlinker CoreFoundation \
    -Xlinker -headerpad_max_install_names

# 2. Create Bundle
DEFAULT_APP_DIR="$HOME/Applications"
mkdir -p "$DEFAULT_APP_DIR"
BUNDLE_NAME="${CODETUNER_APP_DEST:-$DEFAULT_APP_DIR/MicroCode.app}"
rm -rf "$BUNDLE_NAME"
echo "📦 Creating Bundle: $BUNDLE_NAME"
mkdir -p "$BUNDLE_NAME/Contents/MacOS"
mkdir -p "$BUNDLE_NAME/Contents/Resources"

# 3. Copy Binary
BINARY_PATH="$(swift build --show-bin-path)/MicroCode"
if [ ! -f "$BINARY_PATH" ]; then
    BINARY_PATH=".build/out/Products/Debug/MicroCode"
fi
if [ ! -f "$BINARY_PATH" ]; then
    BINARY_PATH=".build/arm64-apple-macosx/debug/MicroCode"
fi
if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    # Try finding it
    BINARY_PATH=$(find .build -name MicroCode -type f | grep -i Products | head -n 1)
    if [ -z "$BINARY_PATH" ]; then
        BINARY_PATH=$(find .build -name MicroCode -type f | head -n 1)
    fi
    if [ -z "$BINARY_PATH" ]; then
        echo "Critical Error: Could not locate compiled binary."
        exit 1
    fi
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
    <string>com.aipreneur.MicroCode</string>
    <key>CFBundleName</key>
    <string>MicroCode</string>
    <key>CFBundleDisplayName</key>
    <string>MicroCode</string>
    <key>CFBundleShortVersionString</key>
    <string>2.3.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
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
            <string>com.aipreneur.MicroCode</string>
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
if [ -f "Secrets.plist" ]; then
    echo "   Copying Secrets.plist..."
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

# Show final size
echo ""
echo "📊 Dev Bundle Size: $(du -sh "$BUNDLE_NAME" | cut -f1)"
echo "✅ Dev Bundle Ready: $BUNDLE_NAME"

# Symlink to root workspace so standard open / shortcuts work with 0 disk overhead on internal drive
rm -rf "MicroCode.app"
ln -sfn "$BUNDLE_NAME" "MicroCode.app"
echo "🔗 Workspace symlink updated: MicroCode.app -> $BUNDLE_NAME"
