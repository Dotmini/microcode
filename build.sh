#!/bin/bash

# MicroCode Build Script
# Builds both Rust backend and SwiftUI frontend

set -e

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

    if [ "$CLEAN" = true ]; then
        echo -e "${YELLOW}Cleaning backend...${NC}"
        cargo clean
    fi

    if [ "$BUILD_TYPE" = "release" ]; then
        echo -e "${YELLOW}Building backend in release mode...${NC}"
        cargo build --release
        BACKEND_PATH="target/release/microcode-backend"
    else
        echo -e "${YELLOW}Building backend in debug mode...${NC}"
        cargo build
        BACKEND_PATH="target/debug/microcode-backend"
    fi

    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ Backend build successful!${NC}"
        echo -e "${GREEN}  Binary location: backend/$BACKEND_PATH${NC}"

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
            xcodebuild clean -project MicroCode.xcodeproj -scheme MicroCode
        fi
    
        echo -e "${YELLOW}Building frontend...${NC}"
        if [ "$BUILD_TYPE" = "release" ]; then
            xcodebuild -project MicroCode.xcodeproj -scheme MicroCode -configuration Release
        else
            xcodebuild -project MicroCode.xcodeproj -scheme MicroCode -configuration Debug
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
            swift package clean
        fi
        
        swift build -c $CONFIG
        
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
    echo -e "  Or:     ${YELLOW}./backend/$BACKEND_PATH${NC}"
    echo ""
fi

if [ "$BACKEND_ONLY" = false ]; then
    echo -e "${GREEN}Frontend:${NC}"
    echo -e "  Open the app from Xcode or the build output"
    echo ""
fi

echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Set your AI API keys in .env or environment variables"
echo -e "  2. Start the backend server"
echo -e "  3. Launch the frontend app"
echo ""
echo -e "${GREEN}Happy coding! 🚀${NC}"
echo ""
