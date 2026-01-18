#!/bin/bash
set -e

APP_NAME="MicroCode"
BUNDLE_ID="com.dotmini.codetunner"
VERSION="1.0.0"

# Directories
BUILD_ROOT=".build_dist"
DIST_ROOT="Dist"

# Clean up
rm -rf "${BUILD_ROOT}"
rm -rf "${DIST_ROOT}"
mkdir -p "${DIST_ROOT}"

# Argument Parsing
DEV_MODE="false"
if [[ "$1" == "--dev" ]]; then
    DEV_MODE="true"
    echo "🚧 DEV MODE ENABLED: Fast build, current arch only, no runtimes, no DMG/PKG."
fi

echo "🚀 Starting Build Process for ${APP_NAME}..."
if [ "$DEV_MODE" = "true" ]; then
    echo "   Mode: DEVELOPMENT (Host Arch Only)"
else
    echo "   Mode: DISTRIBUTION (Universal + Split Arch)"
fi

# ==============================================================================
# 1. COMPILATION PHASE
# ==============================================================================

# Function to build for a specific architecture
compile_arch() {
    ARCH=$1
    echo "========================================"
    echo "🛠️  Compiling for ${ARCH}..."
    echo "========================================"

    ARCH_BUILD_DIR="${BUILD_ROOT}/${ARCH}"
    mkdir -p "${ARCH_BUILD_DIR}"

    # 1.0 Rust Backend & Embedded Lib (Build First for Linking)
    echo "   🦀 Compiling Rust Backend & Embedded Lib..."
    if [ "$ARCH" = "arm64" ]; then
        RUST_TARGET="aarch64-apple-darwin"
    else
        RUST_TARGET="x86_64-apple-darwin"
    fi
    
    cd backend
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" 
    # Build Bin and Lib
    cargo build --release --target "${RUST_TARGET}" --bin codetunner-backend
    cargo build --release --target "${RUST_TARGET}" --lib
    RUST_CONFIG="release"
    cd ..
    
    RUST_LIB_PATH="$(pwd)/backend/target/${RUST_TARGET}/${RUST_CONFIG}"

    # 1.1 Swift App (Main) -- Linking Rust Lib
    echo "   🔨 Compiling Swift App..."
    if [ "$DEV_MODE" = "true" ]; then
        swift build -c release --product CodeTunner --arch "${ARCH}" \
            -Xlinker -L"${RUST_LIB_PATH}" \
            -Xlinker -lcodetunner_embedded
        SWIFT_CONFIG="release"
    else
        swift build -c release --product CodeTunner --arch "${ARCH}" \
            -Xlinker -L"${RUST_LIB_PATH}" \
            -Xlinker -lcodetunner_embedded
        SWIFT_CONFIG="release"
    fi
    
    # Copy Swift Binary
    cp ".build/${ARCH}-apple-macosx/${SWIFT_CONFIG}/CodeTunner" "${ARCH_BUILD_DIR}/CodeTunner"
    
    # Copy Rust Binary
    cp "backend/target/${RUST_TARGET}/${RUST_CONFIG}/codetunner-backend" "${ARCH_BUILD_DIR}/codetunner-backend"

    # 1.3 PreviewAgent (Skipped for now due to dependency issues)
    # PREVIEW_BIN=$(find PreviewAgent/.build -name "PreviewAgent" -type f | grep "${ARCH}" | grep "release" | head -n 1 || true)
    # if [ -n "$PREVIEW_BIN" ]; then
    #    cp "$PREVIEW_BIN" "${ARCH_BUILD_DIR}/PreviewAgent"
    # fi
}

# Function to package an app bundle
package_variant() {
    VARIANT_NAME=$1      # e.g., "MicroCode_ARM64_Full" or "MicroCode_Lite"
    SOURCE_ARCH=$2       # e.g., "arm64", "x86_64", or "universal"
    INCLUDE_RUNTIMES=$3  # "true" or "false"
    OUTPUT_FOLDER=$4     # e.g., "Dist/arm64" or "Dist/Lite"

    echo "========================================"
    echo "📦 Packaging Variant: ${VARIANT_NAME} (${SOURCE_ARCH})"
    echo "========================================"

    mkdir -p "${OUTPUT_FOLDER}"
    APP_BUNDLE="${OUTPUT_FOLDER}/${APP_NAME}.app"
    rm -rf "${APP_BUNDLE}" # Clean previous

    # 2.1 Create Structure
    mkdir -p "${APP_BUNDLE}/Contents/MacOS"
    mkdir -p "${APP_BUNDLE}/Contents/Resources"

    # 2.2 Info.plist
    echo "   📝 Generating Info.plist..."
    cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CodeTunner</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 Dotmini Software. All rights reserved.</string>
</dict>
</plist>
EOF

    # 2.3 Copy Binaries
    echo "   ⚙️  Copying Binaries from ${SOURCE_ARCH}..."
    cp "${BUILD_ROOT}/${SOURCE_ARCH}/CodeTunner" "${APP_BUNDLE}/Contents/MacOS/"
    chmod +x "${APP_BUNDLE}/Contents/MacOS/CodeTunner"
    
    cp "${BUILD_ROOT}/${SOURCE_ARCH}/codetunner-backend" "${APP_BUNDLE}/Contents/MacOS/"
    chmod +x "${APP_BUNDLE}/Contents/MacOS/codetunner-backend"
    
    # CRITICAL: Strip binaries to reduce size (from 200MB+ to ~30-50MB)
    echo "   ✂️  Stripping debug symbols..."
    strip -u -r "${APP_BUNDLE}/Contents/MacOS/CodeTunner"
    strip -u -r "${APP_BUNDLE}/Contents/MacOS/codetunner-backend"

    # PreviewAgent (if exists)
    # if [ -f "${BUILD_ROOT}/${SOURCE_ARCH}/PreviewAgent" ]; then
    #     cp "${BUILD_ROOT}/${SOURCE_ARCH}/PreviewAgent" "${APP_BUNDLE}/Contents/MacOS/"
    #     chmod +x "${APP_BUNDLE}/Contents/MacOS/PreviewAgent"
    # fi

    # 2.4 Bundle Runtimes (If requested)
    if [ "$INCLUDE_RUNTIMES" = "true" ]; then
        echo "   📚 Bundling Runtimes..."
        ./bundle_runtimes.sh "${APP_BUNDLE}" "${SOURCE_ARCH}"
        
        # Create Launchers
        mkdir -p "${APP_BUNDLE}/Contents/Resources/bin"
        create_launcher() {
            NAME=$1
            BIN_PATH=$2
            cat > "${APP_BUNDLE}/Contents/Resources/bin/${NAME}" <<EOF
#!/bin/bash
BASE_DIR="\$(dirname "\$0")/../RuntimeLib"
exec "\$BASE_DIR/${BIN_PATH}" "\$@"
EOF
            chmod +x "${APP_BUNDLE}/Contents/Resources/bin/${NAME}"
        }
        create_launcher "node" "nodejs/bin/node"
        create_launcher "python3" "python/bin/python3"
        create_launcher "go" "go/bin/go"
    else
        echo "   🍃 Lite Version: Skipping Runtime Bundling."
    fi

    # 2.5 Extensions
    echo "   🧩 Bundling Extensions..."
    EXTENSIONS_DIR="${APP_BUNDLE}/Contents/Resources/Extensions"
    mkdir -p "${EXTENSIONS_DIR}"
    if [ -d "Extensions" ]; then
        cp -R Extensions/* "${EXTENSIONS_DIR}/"
    fi

    # 2.5a Icon
    if [ -f "codetunnerxround.icns" ]; then
        echo "   🎨 Copying Icon..."
        cp "codetunnerxround.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    else
        echo "   ⚠️  Warning: codetunnerxround.icns not found!"
    fi

    # 2.6 Signing
    echo "   🔐 Ad-hoc Signing..."
    codesign --force --deep --sign - "${APP_BUNDLE}"

    # 2.7 Create DMG (Skip in Dev Mode)
    if [ "$DEV_MODE" = "false" ]; then
        echo "   💿 Creating DMG..."
        DMG_NAME="${VARIANT_NAME}.dmg"
        hdiutil create -volname "${APP_NAME}" -srcfolder "${OUTPUT_FOLDER}" -ov -format UDZO "${OUTPUT_FOLDER}/${DMG_NAME}"
        echo "      -> Created ${OUTPUT_FOLDER}/${DMG_NAME}"

        # 2.8 Create PKG
        echo "   📦 Creating PKG..."
        PKG_NAME="${VARIANT_NAME}.pkg"
        pkgbuild --root "${APP_BUNDLE}" \
                 --identifier "${BUNDLE_ID}" \
                 --version "${VERSION}" \
                 --install-location "/Applications/${APP_NAME}.app" \
                 "${OUTPUT_FOLDER}/${PKG_NAME}"
        echo "      -> Created ${OUTPUT_FOLDER}/${PKG_NAME}"
    else
        echo "   ⏩ Dev Mode: Skipping DMG/PKG creation."
    fi
}

if [ "$DEV_MODE" = "true" ]; then
    # Detect Host Architecture
    HOST_ARCH=$(uname -m)
    if [ "$HOST_ARCH" = "arm64" ]; then
        compile_arch "arm64"
        package_variant "MicroCode_Dev" "arm64" "false" "Dist/Dev"
    elif [ "$HOST_ARCH" = "x86_64" ]; then
        compile_arch "x86_64"
        package_variant "MicroCode_Dev" "x86_64" "false" "Dist/Dev"
    else
        echo "❌ Unsupported architecture: $HOST_ARCH"
        exit 1
    fi
    
    echo "========================================"
    echo "✅ Dev Build Complete!"
    echo "========================================"
    echo "Artifact: Dist/Dev/MicroCode.app"
    exit 0
fi

compile_arch "arm64"
compile_arch "x86_64"

# 1.4 Create Universal Binaries for Lite Version
echo "========================================"
echo "⚖️  Creating Universal Binaries (Lite)..."
echo "========================================"
UNIVERSAL_BUILD_DIR="${BUILD_ROOT}/universal"
mkdir -p "${UNIVERSAL_BUILD_DIR}"

lipo -create "${BUILD_ROOT}/arm64/CodeTunner" "${BUILD_ROOT}/x86_64/CodeTunner" -output "${UNIVERSAL_BUILD_DIR}/CodeTunner"
lipo -create "${BUILD_ROOT}/arm64/codetunner-backend" "${BUILD_ROOT}/x86_64/codetunner-backend" -output "${UNIVERSAL_BUILD_DIR}/codetunner-backend"

# ==============================================================================
# 2. PACKAGING PHASE
# ==============================================================================



# ==============================================================================
# 3. EXECUTE TARGETS
# ==============================================================================

# Target 1: ARM64 Full
package_variant "MicroCode_ARM64_Full" "arm64" "true" "Dist/arm64"

# Target 2: Intel Full
package_variant "MicroCode_Intel_Full" "x86_64" "true" "Dist/x86_64"

# Target 3: Lite Universal
package_variant "MicroCode_Lite" "universal" "false" "Dist/Lite"

echo "========================================"
echo "🎉 3-Version Build Cycle Complete!"
echo "========================================"
echo "Artifacts:"
echo "1. Dist/arm64/MicroCode_ARM64_Full.dmg"
echo "2. Dist/x86_64/MicroCode_Intel_Full.dmg"
echo "3. Dist/Lite/MicroCode_Lite.dmg (< 50MB)"
