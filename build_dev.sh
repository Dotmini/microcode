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
# We assume Rust lib is at backend/target/debug/libcodetunner_embedded.a
echo "🏗️ Building Swift frontend..."
swift build -c debug \
    -Xlinker -Lbackend/target/debug -Xlinker -lcodetunner_embedded \
    -Xlinker -Lmicrocode_core/target/aarch64-apple-darwin/release -Xlinker -lmicrocode_core

# 2. Create Bundle
BUNDLE_NAME="MicroCode_Dev.app"
echo "📦 Creating Bundle: $BUNDLE_NAME"
rm -rf "$BUNDLE_NAME"
mkdir -p "$BUNDLE_NAME/Contents/MacOS"
mkdir -p "$BUNDLE_NAME/Contents/Resources"

# 3. Copy Binary
# Note: Path might vary depending on swift version/platform, usually arm64-apple-macosx
BINARY_PATH=".build/arm64-apple-macosx/debug/CodeTunner"
if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    # Try finding it
    BINARY_PATH=$(find .build -name CodeTunner -type f | grep debug | head -n 1)
    if [ -z "$BINARY_PATH" ]; then
        echo "Critial Error: Could not locate compiled binary."
        exit 1
    fi
    echo "Found binary at: $BINARY_PATH"
fi

cp "$BINARY_PATH" "$BUNDLE_NAME/Contents/MacOS/"

# 4. Create Info.plist
cat > "$BUNDLE_NAME/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CodeTunner</string>
    <key>CFBundleIdentifier</key>
    <string>com.aipreneur.MicroCode</string>
    <key>CFBundleName</key>
    <string>MicroCode</string>
    <key>CFBundleDisplayName</key>
    <string>MicroCode</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 5. Resources (Logo, etc)
if [ -f "MicroCOdeDoogleIcon.png" ]; then
    echo "   Copying logo..."
    cp "MicroCOdeDoogleIcon.png" "$BUNDLE_NAME/Contents/Resources/"
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
