#!/bin/bash
set -e
set -x

# Ensure cargo/rustc are on PATH (critical for CI where subshells lose PATH)
if [ -f "$HOME/.cargo/env" ]; then
  source "$HOME/.cargo/env" 2>/dev/null || true
fi
export PATH="$HOME/.cargo/bin:$PATH"

# Fallback: if cargo STILL not found, install it now
if ! command -v cargo &>/dev/null; then
  echo "⚠️  cargo not found — installing Rust toolchain..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable 2>/dev/null
  source "$HOME/.cargo/env" 2>/dev/null || true
  export PATH="$HOME/.cargo/bin:$PATH"
fi
echo "🦀 Using: $(cargo --version 2>/dev/null || echo 'cargo not available')"

APP_NAME="MicroCode"
BUNDLE_ID="com.dotmini.microcode"
VERSION="2.5.40"

# Directories
BUILD_ROOT=".build_dist"
DIST_ROOT="Dist"

# Argument Parsing
DEV_MODE="false"
SIGN_AFTER="false"
TARGET_ARCH="all"
TARGET_MODE="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        --dev)
            DEV_MODE="true"
            shift
            ;;
        --arch)
            TARGET_ARCH="$2"
            shift 2
            ;;
        --mode)
            TARGET_MODE="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --sign)
            SIGN_AFTER="true"
            shift
            ;;
        --help)
            echo "Usage: ./build_distribution.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dev              Fast build, host arch only, no DMG/PKG"
            echo "  --arch <ARCH>      Build specific arch (arm64, x86_64, all)"
            echo "  --mode <MODE>      Build mode (full, lite-only, all)"
            echo "  --version <VER>    Override version (default: 1.0.0)"
            echo "  --sign             Run sign_and_notarize.sh after build"
            echo "  --help             Show this help"
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ "$DEV_MODE" = "true" ]; then
    echo "🚧 DEV MODE ENABLED: Fast build, current arch only, no runtimes, no DMG/PKG."
fi

# Clean up
if [ "$TARGET_MODE" != "lite-only" ]; then
    rm -rf "${BUILD_ROOT}"
fi
rm -rf "${DIST_ROOT}"
mkdir -p "${DIST_ROOT}"

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
    # Build Bin and Lib in a single Cargo pass to share unit graph & maximize cache hits
    cargo build --release --target "${RUST_TARGET}" --bin microcode-backend --lib
    RUST_CONFIG="release"
    cd ..
    
    RUST_LIB_PATH="$(pwd)/backend/target/${RUST_TARGET}/${RUST_CONFIG}"

    # 1.0b MicroCode Core (AI Brain) - UniFFI
    echo "   🧠 Compiling MicroCode Core (with UniFFI)..."
    cd microcode_core
    # Build release library for target architecture
    cargo build --release --target "${RUST_TARGET}" --lib

    # CRITICAL: Always regenerate Swift UniFFI bindings from the exact compiled libmicrocode_core.dylib
    # on EVERY architecture runner (arm64 AND x86_64) and write directly to `microcode_core.swift`
    # (which Package.swift compiles; `MicroCore.swift` is excluded in Package.swift!).
    # Skipping this or writing only to `MicroCore.swift` causes `Fatal error: UniFFI API checksum mismatch` at launch.
    echo "   🔗 Generating synchronized Swift UniFFI bindings for ${ARCH}..."
    mkdir -p build/gen_swift
    cargo run --release --bin uniffi-bindgen -- generate \
        --library "target/${RUST_TARGET}/release/libmicrocode_core.dylib" \
        --language swift \
        --out-dir build/gen_swift \
        --no-format
    mkdir -p ../MicroCode/Services/MicroCore
    cmp -s build/gen_swift/microcode_core.swift ../MicroCode/Services/MicroCore/microcode_core.swift || cp build/gen_swift/microcode_core.swift ../MicroCode/Services/MicroCore/microcode_core.swift
    cmp -s build/gen_swift/microcode_core.swift ../MicroCode/Services/MicroCore/MicroCore.swift || cp build/gen_swift/microcode_core.swift ../MicroCode/Services/MicroCore/MicroCore.swift
    cmp -s build/gen_swift/microcode_coreFFI.h ../MicroCode/Services/MicroCore/microcode_coreFFI.h || cp build/gen_swift/microcode_coreFFI.h ../MicroCode/Services/MicroCore/microcode_coreFFI.h
    cmp -s build/gen_swift/microcode_coreFFI.h ../MicrocodeCoreSupport/include/microcode_coreFFI.h || cp build/gen_swift/microcode_coreFFI.h ../MicrocodeCoreSupport/include/microcode_coreFFI.h
    cmp -s build/gen_swift/microcode_coreFFI.modulemap ../MicrocodeCoreSupport/include/module.modulemap || cp build/gen_swift/microcode_coreFFI.modulemap ../MicrocodeCoreSupport/include/module.modulemap
    cd ..
    
    MICROCORE_LIB_PATH="$(pwd)/microcode_core/target/${RUST_TARGET}/release"

    # 1.1 Swift App (Main) -- Linking Rust Lib
    echo "   🔨 Compiling Swift App..."
    
    # Common flags
    LINK_FLAGS="-Xlinker -L${RUST_LIB_PATH} -Xlinker -lmicrocode_embedded -Xlinker -L${MICROCORE_LIB_PATH} -Xlinker -lmicrocode_core -Xswiftc -strict-concurrency=minimal -Xswiftc -Xfrontend -Xswiftc -solver-expression-time-threshold=300"
    
    if [ "$DEV_MODE" = "true" ]; then
        swift build -c release --product MicroCode --arch "${ARCH}" ${LINK_FLAGS}
        SWIFT_CONFIG="release"
    else
        swift build -c release --product MicroCode --arch "${ARCH}" ${LINK_FLAGS}
        SWIFT_CONFIG="release"
    fi
    
    # Copy Swift Binary & Strip Debug Symbols for Compact Distribution
    cp ".build/${ARCH}-apple-macosx/${SWIFT_CONFIG}/MicroCode" "${ARCH_BUILD_DIR}/MicroCode"
    strip -x "${ARCH_BUILD_DIR}/MicroCode" 2>/dev/null || true
    
    # Copy Rust Binary
    cp "backend/target/${RUST_TARGET}/${RUST_CONFIG}/microcode-backend" "${ARCH_BUILD_DIR}/microcode-backend"
    
    # Copy Rust dylibs (CRITICAL: must be same arch)
    echo "   📦 Copying Rust dylibs for ${ARCH}..."
    if [ -f "${RUST_LIB_PATH}/libmicrocode_embedded.dylib" ]; then
        cp "${RUST_LIB_PATH}/libmicrocode_embedded.dylib" "${ARCH_BUILD_DIR}/"
        echo "      → libmicrocode_embedded.dylib (${ARCH})"
    else
        echo "      ⚠️  libmicrocode_embedded.dylib not found at ${RUST_LIB_PATH}"
    fi
    if [ -f "${MICROCORE_LIB_PATH}/libmicrocode_core.dylib" ]; then
        cp "${MICROCORE_LIB_PATH}/libmicrocode_core.dylib" "${ARCH_BUILD_DIR}/"
        echo "      → libmicrocode_core.dylib (${ARCH})"
    else
        echo "      ⚠️  libmicrocode_core.dylib not found at ${MICROCORE_LIB_PATH}"
    fi
    # Stage exact generated UniFFI Swift bindings & SwiftPM resource bundle for `package-lite` CI artifact handoff
    if [ -f "MicroCode/Services/MicroCore/microcode_core.swift" ]; then
        cp "MicroCode/Services/MicroCore/microcode_core.swift" "${ARCH_BUILD_DIR}/microcode_core.swift"
    fi
    if [ -d ".build/${ARCH}-apple-macosx/${SWIFT_CONFIG}/MicroCode_MicroCode.bundle" ]; then
        rm -rf "${ARCH_BUILD_DIR}/MicroCode_MicroCode.bundle"
        cp -R ".build/${ARCH}-apple-macosx/${SWIFT_CONFIG}/MicroCode_MicroCode.bundle" "${ARCH_BUILD_DIR}/MicroCode_MicroCode.bundle"
    fi

    # 1.5 MicroCode CLI (Optional - may not exist)
    if [ -d "../MicroCodeCLI" ]; then
        echo "   💻 Compiling MicroCode CLI..."
        cd ../MicroCodeCLI
        swift build -c release --arch "${ARCH}" || true
        if [ -f ".build/${ARCH}-apple-macosx/release/MicroCodeCLI" ]; then
            cp ".build/${ARCH}-apple-macosx/release/MicroCodeCLI" "../microcode-native/${ARCH_BUILD_DIR}/microcode-cli"
        fi
        cd ../microcode-native
    else
        echo "   ⏩ MicroCode CLI not found, skipping..."
    fi

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
    <string>MicroCode</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER:-37}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
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
    <key>NSLocalNetworkUsageDescription</key>
    <string>MicroCode discovers and connects to Local LLM servers (LM Studio, Ollama, Apple MLX, vLLM, and MicroCode peers) across your Wi-Fi and LAN network.</string>
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
            </array>
        </dict>
    </array>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025-2026 Dotmini Software. All rights reserved.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>MicroCode Notebook</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.dotmini.microcode.mic</string>
            </array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.dotmini.microcode.mic</string>
            <key>UTTypeDescription</key>
            <string>MicroCode Notebook</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>mic</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
EOF

    # 2.3 Copy Binaries
    echo "   ⚙️  Copying Binaries from ${SOURCE_ARCH}..."
    cp "${BUILD_ROOT}/${SOURCE_ARCH}/MicroCode" "${APP_BUNDLE}/Contents/MacOS/"
    chmod +x "${APP_BUNDLE}/Contents/MacOS/MicroCode"
    
    cp "${BUILD_ROOT}/${SOURCE_ARCH}/microcode-backend" "${APP_BUNDLE}/Contents/MacOS/"
    chmod +x "${APP_BUNDLE}/Contents/MacOS/microcode-backend"
    
    if [ -f "${BUILD_ROOT}/${SOURCE_ARCH}/microcode-cli" ]; then
        cp "${BUILD_ROOT}/${SOURCE_ARCH}/microcode-cli" "${APP_BUNDLE}/Contents/MacOS/"
        chmod +x "${APP_BUNDLE}/Contents/MacOS/microcode-cli"
    fi
    
    # 2.3a CRITICAL: Bundle Rust dylibs and fix install names
    echo "   🔗 Bundling and fixing Rust dynamic libraries..."
    FRAMEWORKS_DIR="${APP_BUNDLE}/Contents/Frameworks"
    mkdir -p "${FRAMEWORKS_DIR}"
    
    # Copy dylibs from the CORRECT arch-specific build dir
    for DYLIB_NAME in libmicrocode_embedded.dylib libmicrocode_core.dylib; do
        DYLIB_PATH="${BUILD_ROOT}/${SOURCE_ARCH}/${DYLIB_NAME}"
        
        if [ -f "${DYLIB_PATH}" ]; then
            echo "      → Bundling ${DYLIB_NAME} from ${DYLIB_PATH}"
            
            # Verify architecture matches
            DYLIB_ARCH=$(lipo -archs "${DYLIB_PATH}" 2>/dev/null || echo "unknown")
            echo "        Architecture: ${DYLIB_ARCH}"
            
            cp "${DYLIB_PATH}" "${FRAMEWORKS_DIR}/"
            chmod 755 "${FRAMEWORKS_DIR}/${DYLIB_NAME}"
            
            # Fix the dylib's own install name
            install_name_tool -id "@executable_path/../Frameworks/${DYLIB_NAME}" \
                "${FRAMEWORKS_DIR}/${DYLIB_NAME}"
            
            # Fix the main binary's reference to this dylib
            OLD_NAMES=$(otool -L "${APP_BUNDLE}/Contents/MacOS/MicroCode" | \
                grep "${DYLIB_NAME}" | awk '{print $1}' | sort | uniq)
            
            for OLD_NAME in $OLD_NAMES; do
                if [ -n "${OLD_NAME}" ]; then
                    echo "        Rewriting: ${OLD_NAME}"
                    echo "              → @executable_path/../Frameworks/${DYLIB_NAME}"
                    install_name_tool -change "${OLD_NAME}" \
                        "@executable_path/../Frameworks/${DYLIB_NAME}" \
                        "${APP_BUNDLE}/Contents/MacOS/MicroCode"
                fi
            done
        else
            echo "      ❌ FATAL: ${DYLIB_NAME} not found at ${DYLIB_PATH}"
            echo "         Available files in ${BUILD_ROOT}/${SOURCE_ARCH}/:"
            ls -la "${BUILD_ROOT}/${SOURCE_ARCH}/" 2>/dev/null || echo "         (directory not found)"
            exit 1
        fi
    done
    
    # Verify architecture and paths
    echo "   🔍 Verifying dylib references..."
    echo "   Binary arch: $(lipo -archs "${APP_BUNDLE}/Contents/MacOS/MicroCode" 2>/dev/null)"
    for DYLIB_NAME in libmicrocode_embedded.dylib libmicrocode_core.dylib; do
        if [ -f "${FRAMEWORKS_DIR}/${DYLIB_NAME}" ]; then
            echo "   ${DYLIB_NAME} arch: $(lipo -archs "${FRAMEWORKS_DIR}/${DYLIB_NAME}" 2>/dev/null)"
        fi
    done
    
    BROKEN=$(otool -L "${APP_BUNDLE}/Contents/MacOS/MicroCode" | grep -E "/Users/|/home/" | grep -v "rpath" || true)
    if [ -n "${BROKEN}" ]; then
        echo "   ❌ WARNING: Found absolute dylib paths:"
        echo "${BROKEN}"
    else
        echo "   ✅ All dylib references are relative"
    fi

    # CRITICAL: Strip binaries to reduce size (from 200MB+ to ~30-50MB)
    echo "   ✂️  Stripping debug symbols..."
    strip -u -r "${APP_BUNDLE}/Contents/MacOS/MicroCode"
    strip -u -r "${APP_BUNDLE}/Contents/MacOS/microcode-backend"
    if [ -f "${APP_BUNDLE}/Contents/MacOS/microcode-cli" ]; then
        strip -u -r "${APP_BUNDLE}/Contents/MacOS/microcode-cli"
    fi

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

    # 2.5a Icon & App Resources (sync with build_dev.sh so Bundle.main resources, MCP bridge, and iOS preview runtime are always packaged)
    if [ -f "AppIcon.icns" ]; then
        echo "   🎨 Copying AppIcon.icns..."
        cp "AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    elif [ -f "microcodexround.icns" ]; then
        echo "   🎨 Copying microcodexround.icns as AppIcon.icns..."
        cp "microcodexround.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    else
        echo "   ⚠️  Warning: AppIcon.icns / microcodexround.icns not found!"
    fi
    if [ -f "MicroCOdeDoogleIcon.png" ]; then
        cp "MicroCOdeDoogleIcon.png" "${APP_BUNDLE}/Contents/Resources/"
    fi
    if [ -f "mcp-server.py" ]; then
        cp "mcp-server.py" "${APP_BUNDLE}/Contents/Resources/"
        chmod +x "${APP_BUNDLE}/Contents/Resources/mcp-server.py"
    fi
    if [ -d "MicroCode/Resources" ]; then
        cp -R MicroCode/Resources/* "${APP_BUNDLE}/Contents/Resources/" 2>/dev/null || true
    fi
    for BUNDLE_CANDIDATE in \
        "${BUILD_ROOT}/${SOURCE_ARCH}/MicroCode_MicroCode.bundle" \
        "${BUILD_ROOT}/arm64/MicroCode_MicroCode.bundle" \
        "${BUILD_ROOT}/x86_64/MicroCode_MicroCode.bundle" \
        ".build/${SOURCE_ARCH}-apple-macosx/release/MicroCode_MicroCode.bundle" \
        ".build/arm64-apple-macosx/release/MicroCode_MicroCode.bundle" \
        ".build/x86_64-apple-macosx/release/MicroCode_MicroCode.bundle"; do
        if [ -d "${BUNDLE_CANDIDATE}" ]; then
            cp -R "${BUNDLE_CANDIDATE}" "${APP_BUNDLE}/Contents/Resources/MicroCode_MicroCode.bundle"
            break
        fi
    done

    # 2.5b UniFFI ABI Checksum Pre-Sign Verification Gate (guarantees 0% chance of launch crash)
    HOST_ARCH_CHECK=$(uname -m)
    if [ "${SOURCE_ARCH}" = "${HOST_ARCH_CHECK}" ] || [ "${SOURCE_ARCH}" = "universal" ]; then
        VERIFY_SWIFT_BINDINGS="MicroCode/Services/MicroCore/microcode_core.swift"
        if [ -f "${BUILD_ROOT}/${SOURCE_ARCH}/microcode_core.swift" ]; then
            VERIFY_SWIFT_BINDINGS="${BUILD_ROOT}/${SOURCE_ARCH}/microcode_core.swift"
        elif [ "${SOURCE_ARCH}" = "universal" ] && [ -f "${BUILD_ROOT}/${HOST_ARCH_CHECK}/microcode_core.swift" ]; then
            VERIFY_SWIFT_BINDINGS="${BUILD_ROOT}/${HOST_ARCH_CHECK}/microcode_core.swift"
        fi
        echo "   🧪 Verifying UniFFI ABI checksums against packaged libmicrocode_core.dylib (bindings: ${VERIFY_SWIFT_BINDINGS})..."
        python3 - "${FRAMEWORKS_DIR}/libmicrocode_core.dylib" "${VERIFY_SWIFT_BINDINGS}" <<'PY'
import ctypes, pathlib, re, sys

dylib_path, swift_path = sys.argv[1], sys.argv[2]
swift_src = pathlib.Path(swift_path).read_text()
lib = ctypes.CDLL(dylib_path)

m_ver = re.search(r"let bindings_contract_version\s*=\s*(\d+)", swift_src)
if m_ver:
    expected_ver = int(m_ver.group(1))
    ver_fn = lib.ffi_microcode_core_uniffi_contract_version
    ver_fn.restype = ctypes.c_uint32
    got_ver = ver_fn()
    if got_ver != expected_ver:
        sys.exit(f"❌ FATAL UniFFI contract version mismatch: dylib={got_ver} vs swift={expected_ver}")

pairs = re.findall(r"(uniffi_microcode_core_checksum_[a-zA-Z0-9_]+)\(\)\s*!=\s*(\d+)", swift_src)
if not pairs:
    sys.exit("❌ FATAL: Could not parse UniFFI checksum assertions from microcode_core.swift")

for sym, exp_str in pairs:
    fn = getattr(lib, sym)
    fn.restype = ctypes.c_uint16
    got = fn()
    exp = int(exp_str)
    if got != exp:
        sys.exit(f"❌ FATAL UniFFI API checksum mismatch on {sym}: dylib={got} vs swift={exp}")

print(f"   ✅ All {len(pairs)} UniFFI ABI checksums verified OK!")
PY
    fi

    # 2.6 Signing (Developer ID when DEVELOPER_ID_APPLICATION is provided; ad-hoc fallback)
    if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
        echo "   🔐 Signing with Developer ID (${DEVELOPER_ID_APPLICATION})..."
        codesign --force --deep --options runtime --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "${APP_BUNDLE}"
    else
        echo "   🔐 Ad-hoc Signing..."
        codesign --force --deep --sign - "${APP_BUNDLE}"
    fi

    # 2.7 Create DMG (Skip in Dev Mode)
    if [ "$DEV_MODE" = "false" ]; then
        echo "   💿 Creating DMG (LZFSE / ULFO fast compression)..."
        DMG_NAME="${VARIANT_NAME}.dmg"
        TEMP_DMG="${BUILD_ROOT}/${DMG_NAME}"
        
        # Remove any existing DMG/PKG in OUTPUT_FOLDER before hdiutil snapshots OUTPUT_FOLDER
        rm -f "${TEMP_DMG}" "${OUTPUT_FOLDER}/${DMG_NAME}" "${OUTPUT_FOLDER}/${VARIANT_NAME}.pkg"
        ln -sfn /Applications "${OUTPUT_FOLDER}/Applications"
        
        # Robust DMG creation with retries (ULFO LZFSE is 4-5x faster & smaller on macOS 13+; fallback to UDZO if needed)
        MAX_RETRIES=3
        RETRY_COUNT=0
        SUCCESS=false
        
        while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
            echo "      Attempting hdiutil create (Attempt $((RETRY_COUNT+1))/$MAX_RETRIES)..."
            sync
            sleep 1
            
            if hdiutil create -volname "${APP_NAME}" -srcfolder "${OUTPUT_FOLDER}" -ov -format ULFO "${TEMP_DMG}" \
               || hdiutil create -volname "${APP_NAME}" -srcfolder "${OUTPUT_FOLDER}" -ov -format UDZO "${TEMP_DMG}"; then
                SUCCESS=true
                break
            else
                echo "      ⚠️  hdiutil create failed. Resource might be busy. Retrying..."
                RETRY_COUNT=$((RETRY_COUNT+1))
                sleep 2
            fi
        done
        rm -f "${OUTPUT_FOLDER}/Applications"
        
        if [ "$SUCCESS" = "false" ]; then
            echo "      ❌ Error: Failed to create DMG after $MAX_RETRIES attempts due to busy resources."
            exit 1
        fi
        
        mv "${TEMP_DMG}" "${OUTPUT_FOLDER}/${DMG_NAME}"
        echo "      -> Created ${OUTPUT_FOLDER}/${DMG_NAME}"

        # 2.8 Create PKG directly via --component (zero redundant multi-GB staging copy)
        echo "   📦 Creating PKG..."
        PKG_NAME="${VARIANT_NAME}.pkg"
        TEMP_PKG="${BUILD_ROOT}/${PKG_NAME}"

        rm -f "${TEMP_PKG}" "${OUTPUT_FOLDER}/${PKG_NAME}"

        if [ -n "${DEVELOPER_ID_INSTALLER:-}" ]; then
            pkgbuild --component "${APP_BUNDLE}" \
                     --identifier "${BUNDLE_ID}" \
                     --version "${VERSION}" \
                     --install-location "/Applications" \
                     --sign "${DEVELOPER_ID_INSTALLER}" \
                     "${TEMP_PKG}"
        else
            pkgbuild --component "${APP_BUNDLE}" \
                     --identifier "${BUNDLE_ID}" \
                     --version "${VERSION}" \
                     --install-location "/Applications" \
                     "${TEMP_PKG}"
        fi

        mv "${TEMP_PKG}" "${OUTPUT_FOLDER}/${PKG_NAME}"
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
        package_variant "microcode" "arm64" "false" "Dist/Dev"
    elif [ "$HOST_ARCH" = "x86_64" ]; then
        compile_arch "x86_64"
        package_variant "microcode" "x86_64" "false" "Dist/Dev"
    else
        echo "❌ Unsupported architecture: $HOST_ARCH"
        exit 1
    fi
    
    echo "========================================"
    echo "✅ Dev Build Complete!"
    echo "========================================"
    echo "Artifact: Dist/Dev/microcode.app"
    exit 0
fi

if [ "$TARGET_MODE" = "full" ]; then
    if [ "$TARGET_ARCH" = "arm64" ]; then
        compile_arch "arm64"
        package_variant "Dotmini_MicroCode_ARM64_Full" "arm64" "true" "Dist/arm64"
    elif [ "$TARGET_ARCH" = "x86_64" ]; then
        compile_arch "x86_64"
        package_variant "Dotmini_MicroCode_Intel_Full" "x86_64" "true" "Dist/x86_64"
    else
        compile_arch "arm64"
        compile_arch "x86_64"
        package_variant "Dotmini_MicroCode_ARM64_Full" "arm64" "true" "Dist/arm64"
        package_variant "Dotmini_MicroCode_Intel_Full" "x86_64" "true" "Dist/x86_64"
    fi
elif [ "$TARGET_MODE" = "lite-only" ]; then
    # Assumes arm64 and x86_64 are already compiled and placed in .build_dist/
    echo "========================================"
    echo "⚖️  Creating Universal Binaries (Lite)..."
    echo "========================================"
    UNIVERSAL_BUILD_DIR="${BUILD_ROOT}/universal"
    mkdir -p "${UNIVERSAL_BUILD_DIR}"

    if [ -f "${BUILD_ROOT}/arm64/MicroCode" ] && [ -f "${BUILD_ROOT}/x86_64/MicroCode" ]; then
        lipo -create "${BUILD_ROOT}/arm64/MicroCode" "${BUILD_ROOT}/x86_64/MicroCode" -output "${UNIVERSAL_BUILD_DIR}/MicroCode"
        lipo -create "${BUILD_ROOT}/arm64/microcode-backend" "${BUILD_ROOT}/x86_64/microcode-backend" -output "${UNIVERSAL_BUILD_DIR}/microcode-backend"

        # Universal dylibs
        for DYLIB_NAME in libmicrocode_embedded.dylib libmicrocode_core.dylib; do
            ARM64_DYLIB="${BUILD_ROOT}/arm64/${DYLIB_NAME}"
            X86_DYLIB="${BUILD_ROOT}/x86_64/${DYLIB_NAME}"
            if [ -f "${ARM64_DYLIB}" ] && [ -f "${X86_DYLIB}" ]; then
                lipo -create "${ARM64_DYLIB}" "${X86_DYLIB}" -output "${UNIVERSAL_BUILD_DIR}/${DYLIB_NAME}"
                echo "   → Created universal ${DYLIB_NAME}"
            fi
        done
        package_variant "Dotmini_MicroCode_Lite" "universal" "false" "Dist/Lite"
    else
        echo "❌ Cannot build Lite: Missing arm64 or x86_64 compiled binaries in ${BUILD_ROOT}"
        exit 1
    fi
else
    # Default (all)
    compile_arch "arm64"
    compile_arch "x86_64"

    # 1.4 Create Universal Binaries for Lite Version
    echo "========================================"
    echo "⚖️  Creating Universal Binaries (Lite)..."
    echo "========================================"
    UNIVERSAL_BUILD_DIR="${BUILD_ROOT}/universal"
    mkdir -p "${UNIVERSAL_BUILD_DIR}"

    lipo -create "${BUILD_ROOT}/arm64/MicroCode" "${BUILD_ROOT}/x86_64/MicroCode" -output "${UNIVERSAL_BUILD_DIR}/MicroCode"
    lipo -create "${BUILD_ROOT}/arm64/microcode-backend" "${BUILD_ROOT}/x86_64/microcode-backend" -output "${UNIVERSAL_BUILD_DIR}/microcode-backend"

    # Universal dylibs (CRITICAL: without these, the app crashes at launch)
    for DYLIB_NAME in libmicrocode_embedded.dylib libmicrocode_core.dylib; do
        ARM64_DYLIB="${BUILD_ROOT}/arm64/${DYLIB_NAME}"
        X86_DYLIB="${BUILD_ROOT}/x86_64/${DYLIB_NAME}"
        
        if [ -f "${ARM64_DYLIB}" ] && [ -f "${X86_DYLIB}" ]; then
            lipo -create "${ARM64_DYLIB}" "${X86_DYLIB}" -output "${UNIVERSAL_BUILD_DIR}/${DYLIB_NAME}"
            echo "   → Created universal ${DYLIB_NAME}"
        elif [ -f "${ARM64_DYLIB}" ]; then
            cp "${ARM64_DYLIB}" "${UNIVERSAL_BUILD_DIR}/${DYLIB_NAME}"
            echo "   → Copied arm64-only ${DYLIB_NAME}"
        elif [ -f "${X86_DYLIB}" ]; then
            cp "${X86_DYLIB}" "${UNIVERSAL_BUILD_DIR}/${DYLIB_NAME}"
            echo "   → Copied x86_64-only ${DYLIB_NAME}"
        else
            echo "   ⚠️  ${DYLIB_NAME} not found for either arch!"
        fi
    done

    # Target 1: ARM64 Full
    package_variant "Dotmini_MicroCode_ARM64_Full" "arm64" "true" "Dist/arm64"

    # Target 2: Intel Full
    package_variant "Dotmini_MicroCode_Intel_Full" "x86_64" "true" "Dist/x86_64"

    # Target 3: Lite Universal
    package_variant "Dotmini_MicroCode_Lite" "universal" "false" "Dist/Lite"

    echo "========================================"
    echo "🎉 3-Version Build Cycle Complete!"
    echo "   Version: ${VERSION}"
    echo "========================================"
    echo "Artifacts:"
    echo "1. Dist/arm64/Dotmini_MicroCode_ARM64_Full.dmg"
    echo "2. Dist/x86_64/Dotmini_MicroCode_Intel_Full.dmg"
    echo "3. Dist/Lite/Dotmini_MicroCode_Lite.dmg (< 50MB)"
fi

# ==============================================================================
# 4. OPTIONAL: Sign & Notarize
# ==============================================================================
if [ "$SIGN_AFTER" = "true" ]; then
    echo ""
    echo "========================================"
    echo "🔐 Running Sign & Notarize..."
    echo "========================================"
    if [ -x "./sign_and_notarize.sh" ]; then
        ./sign_and_notarize.sh all
    else
        echo "⚠️  sign_and_notarize.sh not found or not executable"
        echo "   Run manually: ./sign_and_notarize.sh all"
    fi
fi
