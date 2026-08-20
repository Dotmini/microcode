#!/bin/bash

# MicroCode Build Script
# Builds both Rust backend and SwiftUI frontend

set -e

# Keep generated build products and downloaded package caches off the internal
# drive when the configured external volume is available. Override this path
# with CODETUNER_BUILD_ROOT when using a different volume or directory.
DEFAULT_BUILD_ROOT="/Volumes/MAC/CodeTunerBuild"
if [ -n "${CODETUNER_BUILD_ROOT:-}" ]; then
    BUILD_ROOT="$CODETUNER_BUILD_ROOT"
elif [ -d "/Volumes/MAC" ]; then
    BUILD_ROOT="$DEFAULT_BUILD_ROOT"
else
    BUILD_ROOT="$(pwd)/.codetuner-build"
    echo "Warning: /Volumes/MAC is not mounted; using local build cache at $BUILD_ROOT"
fi

mkdir -p "$BUILD_ROOT/cargo-home" "$BUILD_ROOT/cargo-target" "$BUILD_ROOT/rustup-home" "$BUILD_ROOT/swiftpm" "$BUILD_ROOT/derived-data" "$BUILD_ROOT/tmp"
export TMPDIR="$BUILD_ROOT/tmp"
export CARGO_HOME="$BUILD_ROOT/cargo-home"
export CARGO_TARGET_DIR="$BUILD_ROOT/cargo-target"
export RUSTUP_HOME="$BUILD_ROOT/rustup-home"
export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1
SWIFT_SCRATCH_PATH="$BUILD_ROOT/swiftpm/$(basename "$PWD")"
XCODE_DERIVED_DATA_PATH="$BUILD_ROOT/derived-data/$(basename "$PWD")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                                               ║${NC}"
echo -e "${GREEN}║                              MicroCode Build Script                          ║${NC}"
echo -e "${GREEN}║                              By SPU AI CLUB                                   ║${NC}"
echo -e "${GREEN}║                                                                               ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if we're in the right directory
if [ ! -d "backend" ] || [ ! -d "MicroCode" ]; then
    echo -e "${RED}Error: This script must be run from the microcode-native directory${NC}"
    exit 1
fi

# Parse command line arguments
BUILD_TYPE="release"
BACKEND_ONLY=false
FRONTEND_ONLY=false
CLEAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            BUILD_TYPE="debug"
            shift
            ;;
        --backend-only)
            BACKEND_ONLY=true
            shift
            ;;
        --frontend-only)
            FRONTEND_ONLY=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --help)
            echo "Usage: ./build.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --debug           Build in debug mode (default: release)"
            echo "  --backend-only    Only build the Rust backend"
            echo "  --frontend-only   Only build the SwiftUI frontend"
            echo "  --clean           Clean before building"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command_exists rustc; then
    echo -e "${RED}Error: Rust is not installed${NC}"
    echo "Install from: https://rustup.rs/"
    exit 1
fi

if ! command_exists cargo; then
    echo -e "${RED}Error: Cargo is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Rust $(rustc --version)${NC}"
echo -e "${GREEN}✓ Cargo $(cargo --version)${NC}"
echo -e "${GREEN}✓ Build/cache root: $BUILD_ROOT${NC}"

# Set deployment target for both Rust and Swift
export MACOSX_DEPLOYMENT_TARGET=12.0

# Build Backend
if [ "$FRONTEND_ONLY" = false ]; then
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Building Rust Backend...${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""

    cd backend

    # Non-APFS external volumes may materialize macOS extended attributes as
    # AppleDouble files. Some native crates (notably ring 0.16) reject unknown
    # files while scanning their source tree, so fetch first and remove only
    # this generated metadata from Cargo's cache.
    cargo fetch
    find "$CARGO_HOME" -type f -name '._*' -delete

    if [ "$CLEAN" = true ]; then
        echo -e "${YELLOW}Cleaning backend...${NC}"
        cargo clean
    fi

    if [ "$BUILD_TYPE" = "release" ]; then
        echo -e "${YELLOW}Building backend in release mode...${NC}"
        cargo build --release
        BACKEND_PATH="$CARGO_TARGET_DIR/release/microcode-backend"
    else
        echo -e "${YELLOW}Building backend in debug mode...${NC}"
        cargo build
        BACKEND_PATH="$CARGO_TARGET_DIR/debug/microcode-backend"
    fi

    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ Backend build successful!${NC}"
        echo -e "${GREEN}  Binary location: $BACKEND_PATH${NC}"

        # Get binary size
        if [ -f "$BACKEND_PATH" ]; then
            SIZE=$(du -h "$BACKEND_PATH" | cut -f1)
            echo -e "${GREEN}  Binary size: $SIZE${NC}"
        fi
    else
        echo -e "${RED}✗ Backend build failed!${NC}"
        exit 1
    fi

    cd ..
fi

# Build Frontend
if [ "$BACKEND_ONLY" = false ]; then
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Building SwiftUI Frontend...${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""

    if ! command_exists xcodebuild; then
        echo -e "${RED}Error: Xcode is not installed${NC}"
        echo "Install from Mac App Store"
        exit 1
    fi

    # Check if project file exists
    if [ -f "MicroCode.xcodeproj/project.pbxproj" ]; then
        if [ "$CLEAN" = true ]; then
            echo -e "${YELLOW}Cleaning frontend...${NC}"
            xcodebuild clean -project MicroCode.xcodeproj -scheme MicroCode -derivedDataPath "$XCODE_DERIVED_DATA_PATH"
        fi
    
        echo -e "${YELLOW}Building frontend...${NC}"
        if [ "$BUILD_TYPE" = "release" ]; then
            xcodebuild -project MicroCode.xcodeproj -scheme MicroCode -configuration Release -derivedDataPath "$XCODE_DERIVED_DATA_PATH"
        else
            xcodebuild -project MicroCode.xcodeproj -scheme MicroCode -configuration Debug -derivedDataPath "$XCODE_DERIVED_DATA_PATH"
        fi
    
        if [ $? -eq 0 ]; then
            echo ""
            echo -e "${GREEN}✓ Frontend build successful!${NC}"
        else
            echo -e "${RED}✗ Frontend build failed!${NC}"
            exit 1
        fi
elif [ -f "Package.swift" ]; then
        echo -e "${YELLOW}Building with Swift Package Manager...${NC}"
        
        CONFIG="debug"
        if [ "$BUILD_TYPE" = "release" ]; then
            CONFIG="release"
        fi
        
        if [ "$CLEAN" = true ]; then
            echo -e "${YELLOW}Cleaning frontend...${NC}"
            swift package clean --scratch-path "$SWIFT_SCRATCH_PATH"
        fi

        # SwiftPM compiles the C/Objective-C bridges but does not know how to
        # build or link their Rust implementations. Build both static libraries
        # explicitly and pass their external target directory to the linker.
        echo -e "${YELLOW}Building Rust FFI libraries...${NC}"
        cargo fetch --manifest-path backend/Cargo.toml
        cargo fetch --manifest-path microcode_core/Cargo.toml
        find "$CARGO_HOME" -type f -name '._*' -delete

        if [ "$CONFIG" = "release" ]; then
            cargo build --manifest-path backend/Cargo.toml --lib --release
            cargo build --manifest-path microcode_core/Cargo.toml --release
            RUST_LIB_DIR="$CARGO_TARGET_DIR/release"
        else
            cargo build --manifest-path backend/Cargo.toml --lib
            cargo build --manifest-path microcode_core/Cargo.toml
            RUST_LIB_DIR="$CARGO_TARGET_DIR/debug"
        fi

        swift build -c "$CONFIG" --scratch-path "$SWIFT_SCRATCH_PATH" \
            -Xlinker "$RUST_LIB_DIR/libmicrocode_embedded.a" \
            -Xlinker "$RUST_LIB_DIR/libmicrocode_core.a" \
            -Xlinker -framework -Xlinker SystemConfiguration \
            -Xlinker -framework -Xlinker Security \
            -Xlinker -framework -Xlinker CoreFoundation

        echo -e "${YELLOW}Packaging MicroCode.app...${NC}"
        SWIFT_BIN_PATH="$SWIFT_SCRATCH_PATH/$CONFIG/MicroCode"
        BACKEND_BIN_PATH="$CARGO_TARGET_DIR/$CONFIG/microcode-backend"
        APP_BUNDLE="$BUILD_ROOT/apps/MicroCode.app"

        if [ ! -f "$SWIFT_BIN_PATH" ] || [ ! -f "$BACKEND_BIN_PATH" ]; then
            echo -e "${RED}Error: Required app binaries were not found.${NC}"
            echo "Frontend: $SWIFT_BIN_PATH"
            echo "Backend:  $BACKEND_BIN_PATH"
            exit 1
        fi

        rm -rf "$APP_BUNDLE"
        mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
        cp "$SWIFT_BIN_PATH" "$APP_BUNDLE/Contents/MacOS/MicroCode"
        cp "$BACKEND_BIN_PATH" "$APP_BUNDLE/Contents/MacOS/microcode-backend"
        chmod +x "$APP_BUNDLE/Contents/MacOS/MicroCode" "$APP_BUNDLE/Contents/MacOS/microcode-backend"

        if [ -f "microcodexround.icns" ]; then
            cp "microcodexround.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
        fi
        if [ -d "Extensions" ]; then
            mkdir -p "$APP_BUNDLE/Contents/Resources/Extensions"
            cp -R "Extensions/." "$APP_BUNDLE/Contents/Resources/Extensions/"
        fi
        if [ -f "mcp-server.py" ]; then
            cp "mcp-server.py" "$APP_BUNDLE/Contents/Resources/mcp-server.py"
            chmod 644 "$APP_BUNDLE/Contents/Resources/mcp-server.py"
        fi

        cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleURLName</key>
            <string>com.dotmini.microcode</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>microcode</string>
                <string>codetuner</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

        # exFAT may store macOS metadata as AppleDouble files, which codesign
        # treats as invalid nested bundle content.
        find "$APP_BUNDLE" -type f -name '._*' -delete
        codesign --force --deep --sign - "$APP_BUNDLE"
        echo -e "${GREEN}✓ App bundle: $APP_BUNDLE${NC}"
        
        if [ $? -eq 0 ]; then
             echo ""
             echo -e "${GREEN}✓ Frontend (SwiftPM) build successful!${NC}"
        else
             echo -e "${RED}✗ Frontend (SwiftPM) build failed!${NC}"
             exit 1
        fi
    else
        echo -e "${YELLOW}Note: Xcode project not found. Creating a basic structure...${NC}"
        echo -e "${YELLOW}You will need to create the Xcode project manually.${NC}"
        echo ""
        echo "To create the Xcode project:"
        echo "1. Open Xcode"
        echo "2. File → New → Project"
        echo "3. Choose macOS → App"
        echo "4. Name: MicroCode"
        echo "5. Interface: SwiftUI"
        echo "6. Language: Swift"
        echo "7. Add the files from the MicroCode directory"
        echo ""
        exit 0
    fi
fi

# Summary
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

if [ "$FRONTEND_ONLY" = false ]; then
    echo -e "${GREEN}Backend:${NC}"
    echo -e "  To run: ${YELLOW}cd backend && cargo run --release${NC}"
    echo -e "  Or:     ${YELLOW}$BACKEND_PATH${NC}"
    echo ""
fi

if [ "$BACKEND_ONLY" = false ]; then
    echo -e "${GREEN}Frontend:${NC}"
    if [ -n "${APP_BUNDLE:-}" ]; then
        echo -e "  App: ${YELLOW}$APP_BUNDLE${NC}"
        echo -e "  Open: ${YELLOW}open \"$APP_BUNDLE\"${NC}"
    else
        echo -e "  Open the app from Xcode or the build output"
    fi
    echo ""
fi

echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Set your AI API keys in .env or environment variables"
echo -e "  2. Start the backend server"
echo -e "  3. Launch the frontend app"
echo ""
echo -e "${GREEN}Happy coding! 🚀${NC}"
echo ""
