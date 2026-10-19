#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  MicroCode Native IDE & Portable Polyglot Runtime Installer              ║
# ║  Thailand's 1st Sovereign AI IDE — https://microcode.dotmini.net         ║
# ║  One-liner: curl -fsSL https://microcode.dotmini.net/install.sh | bash   ║
# ╚══════════════════════════════════════════════════════════════════════════╝
set -e

BOLD="\033[1m"
CYAN="\033[36m"
PINK="\033[35m"
GREEN="\033[32m"
YELLOW="\033[33m"
DIM="\033[2m"
RESET="\033[0m"

RUNTIMES_ONLY=false
SKIP_RUNTIMES=false
for arg in "$@"; do
    case "$arg" in
        --runtimes-only) RUNTIMES_ONLY=true ;;
        --skip-runtimes) SKIP_RUNTIMES=true ;;
    esac
done

echo -e "${PINK}
    __  ____                 ______          __   
   /  |/  (_)_____________  / ____/___  ____/ /__ 
  / /|_/ / / ___/ ___/ __ \/ /   / __ \/ __  / _ \\
 / /  / / / /__/ /  / /_/ / /___/ /_/ / /_/ /  __/
/_/  /_/_/\___/_/   \____/\____/\____/\__,_/\___/ 
${RESET}"
echo -e "${BOLD}${CYAN}Thailand's 1st Sovereign AI IDE${RESET} — Native. Faster. Smoother."
echo -e "${DIM}Website: https://microcode.dotmini.net${RESET}"
echo -e "${DIM}Crafted by Dotmini Software · SPU AI CLUB${RESET}\n"

OS="$(uname -s)"
ARCH="$(uname -m)"

if [ "$OS" != "Darwin" ]; then
    echo -e "${YELLOW}Notice:${RESET} MicroCode Native IDE is currently optimized for macOS (Apple Silicon & Intel)."
    echo -e "Windows & Linux builds are scheduled for public beta release soon."
    echo -e "Register for early access at: ${CYAN}https://microcode.dotmini.net/#download${RESET}"
    exit 0
fi

echo -e "${GREEN}✓${RESET} Detected macOS (${ARCH})"

# Determine target Applications folder
TARGET_DIR="/Applications"
if [ ! -w "$TARGET_DIR" ]; then
    TARGET_DIR="$HOME/Applications"
    mkdir -p "$TARGET_DIR"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 1: Install MicroCode.app (unless --runtimes-only is specified)
# ═══════════════════════════════════════════════════════════════════════════
if [ "$RUNTIMES_ONLY" = false ]; then
    echo -e "${CYAN}→${RESET} Resolving latest MicroCode release..."

    DMG_URL=""
    VERSION_TAG=""

    # 1. Check live API on microcode.dotmini.net (synced with GitHub releases)
    API_RESP="$(curl -fsSL --max-time 4 "https://microcode.dotmini.net/api/release/latest" 2>/dev/null || true)"
    if [ -n "$API_RESP" ]; then
        VERSION_TAG="$(echo "$API_RESP" | grep -o '"version":"[^"]*' | head -n 1 | cut -d'"' -f4)"
        FETCHED_DMG="$(echo "$API_RESP" | grep -o '"dmg_url":"[^"]*' | head -n 1 | cut -d'"' -f4)"
        if [ -n "$FETCHED_DMG" ]; then
            DMG_URL="$FETCHED_DMG"
        fi
    fi

    # 2. Fallback directly to GitHub Releases API if needed
    if [ -z "$DMG_URL" ] || [[ "$DMG_URL" == /* ]]; then
        GH_DMG="$(curl -fsSL --max-time 4 "https://api.github.com/repos/Dotmini/microcode/releases/latest" 2>/dev/null | grep "browser_download_url.*\.dmg" | head -n 1 | cut -d : -f 2,3 | tr -d '" ' || true)"
        if [ -n "$GH_DMG" ]; then
            DMG_URL="$GH_DMG"
        elif [[ "$DMG_URL" == /* ]]; then
            DMG_URL="https://microcode.dotmini.net${DMG_URL}"
        fi
    fi

    # 3. Fallback to server redirect if all else fails
    if [ -z "$DMG_URL" ]; then
        DMG_URL="https://microcode.dotmini.net/downloads/latest.dmg"
    fi

    if [ -n "$VERSION_TAG" ]; then
        echo -e "${CYAN}→${RESET} Target: MicroCode v${VERSION_TAG} (Universal Apple Silicon & Intel)"
    else
        echo -e "${CYAN}→${RESET} Target: MicroCode Latest Release (Universal Apple Silicon & Intel)"
    fi

    TEMP_DMG="/tmp/MicroCode-Installer.dmg"
    MOUNT_POINT="/Volumes/MicroCode"

    # Cleanup previous mount or temp files if any
    if [ -d "$MOUNT_POINT" ]; then
        hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
    fi
    rm -f "$TEMP_DMG"

    echo -e "${CYAN}→${RESET} Downloading MicroCode package..."
    if command -v curl >/dev/null 2>&1; then
        curl -# -fSL "$DMG_URL" -o "$TEMP_DMG" || true
    else
        wget --progress=bar:force -O "$TEMP_DMG" "$DMG_URL" || true
    fi

    if [ -f "$TEMP_DMG" ] && [ -s "$TEMP_DMG" ]; then
        echo -e "${CYAN}→${RESET} Mounting installer package..."
        hdiutil attach "$TEMP_DMG" -nobrowse -readonly -mountpoint "$MOUNT_POINT" >/dev/null 2>&1 || \
        hdiutil attach "$TEMP_DMG" -nobrowse -readonly >/dev/null 2>&1 || true

        APP_SRC=""
        if [ -d "$MOUNT_POINT/MicroCode.app" ]; then
            APP_SRC="$MOUNT_POINT/MicroCode.app"
        elif [ -d "/Volumes/MicroCode/MicroCode.app" ]; then
            APP_SRC="/Volumes/MicroCode/MicroCode.app"
        else
            FOUND_APP="$(find /Volumes -maxdepth 2 -name "MicroCode.app" 2>/dev/null | head -n 1)"
            if [ -n "$FOUND_APP" ]; then
                APP_SRC="$FOUND_APP"
            fi
        fi

        if [ -n "$APP_SRC" ]; then
            echo -e "${CYAN}→${RESET} Installing to ${TARGET_DIR}/MicroCode.app..."
            rm -rf "${TARGET_DIR}/MicroCode.app"
            cp -R "$APP_SRC" "${TARGET_DIR}/"
        fi

        hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || hdiutil detach "/Volumes/MicroCode" -force >/dev/null 2>&1 || true
        rm -f "$TEMP_DMG"
        xattr -dr com.apple.quarantine "${TARGET_DIR}/MicroCode.app" 2>/dev/null || true
    elif [ -d "${TARGET_DIR}/MicroCode.app" ]; then
        echo -e "${GREEN}✓${RESET} Existing ${TARGET_DIR}/MicroCode.app detected — proceeding to portable runtime provisioning."
    else
        echo -e "${YELLOW}Notice:${RESET} Could not download DMG directly. Provisioning runtimes and opening download page..."
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 2: Provision Portable Polyglot Runtimes for Playground & Cell Mode
# ═══════════════════════════════════════════════════════════════════════════
RUNTIMES_ROOT="$HOME/Library/Application Support/MicroCode/Runtimes"
DOWNLOAD_TMP="/tmp/microcode_runtime_setup_$$"

install_portable_runtimes() {
    echo -e "\n${BOLD}${CYAN}⚡ Provisioning Zero-Dependency Runtimes (Playground & Cell Mode)${RESET}"
    echo -e "${DIM}Destination: ${RUNTIMES_ROOT}${RESET}"
    mkdir -p "$RUNTIMES_ROOT" "$DOWNLOAD_TMP"

    local is_arm=false
    if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
        is_arm=true
    fi

    # 1. Python 3.12 (Standalone)
    if [ ! -x "$RUNTIMES_ROOT/python/bin/python3" ]; then
        echo -e "${CYAN}→${RESET} Installing portable ${BOLD}Python 3.12${RESET} (for Cell Mode & Playground)..."
        local py_tag="20241016"
        local py_ver="3.12.7"
        local py_target="x86_64-apple-darwin"
        if [ "$is_arm" = true ]; then py_target="aarch64-apple-darwin"; fi
        local py_url="https://github.com/indygreg/python-build-standalone/releases/download/${py_tag}/cpython-${py_ver}+${py_tag}-${py_target}-install_only.tar.gz"
        if curl -fsSL --retry 2 "$py_url" -o "$DOWNLOAD_TMP/python.tar.gz"; then
            rm -rf "$RUNTIMES_ROOT/python" && mkdir -p "$RUNTIMES_ROOT/python"
            tar -xzf "$DOWNLOAD_TMP/python.tar.gz" -C "$RUNTIMES_ROOT/python" --strip-components=1
            rm -rf "$RUNTIMES_ROOT/python/share" "$RUNTIMES_ROOT/python/lib/python3.12/test" "$RUNTIMES_ROOT/python/lib/python3.12/idlelib"
            echo -e "  ${GREEN}✓${RESET} Python ready: $($RUNTIMES_ROOT/python/bin/python3 --version 2>/dev/null || echo '3.12.7')"
        fi
    else
        echo -e "  ${GREEN}✓${RESET} Python already installed ($($RUNTIMES_ROOT/python/bin/python3 --version 2>/dev/null))"
    fi

    # 2. Node.js v22 LTS
    if [ ! -x "$RUNTIMES_ROOT/nodejs/bin/node" ]; then
        echo -e "${CYAN}→${RESET} Installing portable ${BOLD}Node.js v22 LTS${RESET}..."
        local node_ver="22.14.0"
        local node_target="darwin-x64"
        if [ "$is_arm" = true ]; then node_target="darwin-arm64"; fi
        local node_url="https://nodejs.org/dist/v${node_ver}/node-v${node_ver}-${node_target}.tar.gz"
        if curl -fsSL --retry 2 "$node_url" -o "$DOWNLOAD_TMP/node.tar.gz"; then
            rm -rf "$RUNTIMES_ROOT/nodejs" && mkdir -p "$RUNTIMES_ROOT/nodejs"
            tar -xzf "$DOWNLOAD_TMP/node.tar.gz" -C "$RUNTIMES_ROOT/nodejs" --strip-components=1
            rm -rf "$RUNTIMES_ROOT/nodejs/share"
            echo -e "  ${GREEN}✓${RESET} Node.js ready: $($RUNTIMES_ROOT/nodejs/bin/node --version 2>/dev/null || echo 'v22.14.0')"
        fi
    else
        echo -e "  ${GREEN}✓${RESET} Node.js already installed ($($RUNTIMES_ROOT/nodejs/bin/node --version 2>/dev/null))"
    fi

    # 3. Bun (Fast JS & TypeScript Runtime)
    if [ ! -x "$RUNTIMES_ROOT/bun/bin/bun" ]; then
        echo -e "${CYAN}→${RESET} Installing portable ${BOLD}Bun (TypeScript/JS)${RESET}..."
        local bun_file="bun-darwin-x64.zip"
        if [ "$is_arm" = true ]; then bun_file="bun-darwin-aarch64.zip"; fi
        local bun_url="https://github.com/oven-sh/bun/releases/latest/download/${bun_file}"
        if curl -fsSL --retry 2 "$bun_url" -o "$DOWNLOAD_TMP/bun.zip"; then
            rm -rf "$RUNTIMES_ROOT/bun" && mkdir -p "$RUNTIMES_ROOT/bun/bin"
            unzip -qo "$DOWNLOAD_TMP/bun.zip" -d "$DOWNLOAD_TMP/bun_ext"
            find "$DOWNLOAD_TMP/bun_ext" -name "bun" -type f -exec mv {} "$RUNTIMES_ROOT/bun/bin/bun" \;
            chmod +x "$RUNTIMES_ROOT/bun/bin/bun"
            ln -sf "$RUNTIMES_ROOT/bun/bin/bun" "$RUNTIMES_ROOT/bun/bin/bunx" 2>/dev/null || true
            echo -e "  ${GREEN}✓${RESET} Bun ready: v$($RUNTIMES_ROOT/bun/bin/bun --version 2>/dev/null || echo 'latest')"
        fi
    else
        echo -e "  ${GREEN}✓${RESET} Bun already installed (v$($RUNTIMES_ROOT/bun/bin/bun --version 2>/dev/null))"
    fi

    # 4. Deno (TypeScript Runtime)
    if [ ! -x "$RUNTIMES_ROOT/deno/bin/deno" ]; then
        echo -e "${CYAN}→${RESET} Installing portable ${BOLD}Deno${RESET}..."
        local deno_file="deno-x86_64-apple-darwin.zip"
        if [ "$is_arm" = true ]; then deno_file="deno-aarch64-apple-darwin.zip"; fi
        local deno_url="https://github.com/denoland/deno/releases/latest/download/${deno_file}"
        if curl -fsSL --retry 2 "$deno_url" -o "$DOWNLOAD_TMP/deno.zip"; then
            rm -rf "$RUNTIMES_ROOT/deno" && mkdir -p "$RUNTIMES_ROOT/deno/bin"
            unzip -qo "$DOWNLOAD_TMP/deno.zip" -d "$RUNTIMES_ROOT/deno/bin"
            chmod +x "$RUNTIMES_ROOT/deno/bin/deno"
            echo -e "  ${GREEN}✓${RESET} Deno ready: $($RUNTIMES_ROOT/deno/bin/deno --version 2>/dev/null | head -n 1 || echo 'latest')"
        fi
    else
        echo -e "  ${GREEN}✓${RESET} Deno already installed"
    fi

    # 5. Go 1.23
    if [ ! -x "$RUNTIMES_ROOT/go/bin/go" ]; then
        echo -e "${CYAN}→${RESET} Installing portable ${BOLD}Go 1.23${RESET}..."
        local go_ver="1.23.4"
        local go_target="darwin-amd64"
        if [ "$is_arm" = true ]; then go_target="darwin-arm64"; fi
        local go_url="https://go.dev/dl/go${go_ver}.${go_target}.tar.gz"
        if curl -fsSL --retry 2 "$go_url" -o "$DOWNLOAD_TMP/go.tar.gz"; then
            rm -rf "$RUNTIMES_ROOT/go" && mkdir -p "$RUNTIMES_ROOT/go"
            tar -xzf "$DOWNLOAD_TMP/go.tar.gz" -C "$RUNTIMES_ROOT/go" --strip-components=1
            rm -rf "$RUNTIMES_ROOT/go/doc" "$RUNTIMES_ROOT/go/test"
            echo -e "  ${GREEN}✓${RESET} Go ready: $($RUNTIMES_ROOT/go/bin/go version 2>/dev/null || echo 'go1.23.4')"
        fi
    else
        echo -e "  ${GREEN}✓${RESET} Go already installed ($($RUNTIMES_ROOT/go/bin/go version 2>/dev/null))"
    fi

    # 6. Java JDK 21 (Eclipse Temurin with javac + java)
    if [ ! -x "$RUNTIMES_ROOT/java/bin/javac" ]; then
        echo -e "${CYAN}→${RESET} Installing portable ${BOLD}Java JDK 21 (Temurin)${RESET}..."
        local java_arch="x64"
        if [ "$is_arm" = true ]; then java_arch="aarch64"; fi
        local java_url="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jdk_${java_arch}_mac_hotspot_21.0.5_11.tar.gz"
        if curl -fsSL --retry 2 "$java_url" -o "$DOWNLOAD_TMP/java.tar.gz"; then
            rm -rf "$RUNTIMES_ROOT/java" "$DOWNLOAD_TMP/java_ext"
            mkdir -p "$RUNTIMES_ROOT/java" "$DOWNLOAD_TMP/java_ext"
            tar -xzf "$DOWNLOAD_TMP/java.tar.gz" -C "$DOWNLOAD_TMP/java_ext" --strip-components=1
            if [ -d "$DOWNLOAD_TMP/java_ext/Contents/Home" ]; then
                cp -R "$DOWNLOAD_TMP/java_ext/Contents/Home/." "$RUNTIMES_ROOT/java/"
            else
                cp -R "$DOWNLOAD_TMP/java_ext/." "$RUNTIMES_ROOT/java/"
            fi
            rm -rf "$RUNTIMES_ROOT/java/man" "$RUNTIMES_ROOT/java/legal" "$RUNTIMES_ROOT/java/demo"
            echo -e "  ${GREEN}✓${RESET} Java JDK 21 ready: $($RUNTIMES_ROOT/java/bin/java -version 2>&1 | head -n 1 || echo 'JDK 21')"
        fi
    else
        echo -e "  ${GREEN}✓${RESET} Java JDK 21 already installed"
    fi

    # 7. Portable C / C++ Toolchain (Zig cc / c++ drop-in clang / clang++)
    if [ ! -x "/Library/Developer/CommandLineTools/usr/bin/clang" ] && [ ! -x "/Applications/Xcode.app/Contents/Developer/usr/bin/clang" ] && [ ! -x "$RUNTIMES_ROOT/c/bin/clang" ]; then
        echo -e "${CYAN}→${RESET} Installing portable ${BOLD}C / C++ Compiler (Zig LLVM Drop-in)${RESET}..."
        local zig_arch="x86_64"
        if [ "$is_arm" = true ]; then zig_arch="aarch64"; fi
        local zig_url="https://ziglang.org/download/0.13.0/zig-macos-${zig_arch}-0.13.0.tar.xz"
        if curl -fsSL --retry 2 "$zig_url" -o "$DOWNLOAD_TMP/zig.tar.xz"; then
            rm -rf "$RUNTIMES_ROOT/zig" "$RUNTIMES_ROOT/c" "$RUNTIMES_ROOT/cpp"
            mkdir -p "$RUNTIMES_ROOT/zig" "$RUNTIMES_ROOT/c/bin" "$RUNTIMES_ROOT/cpp/bin"
            tar -xJf "$DOWNLOAD_TMP/zig.tar.xz" -C "$RUNTIMES_ROOT/zig" --strip-components=1
            cat > "$RUNTIMES_ROOT/c/bin/clang" <<EOF
#!/bin/sh
exec "$RUNTIMES_ROOT/zig/zig" cc "\$@"
EOF
            cat > "$RUNTIMES_ROOT/cpp/bin/clang++" <<EOF
#!/bin/sh
exec "$RUNTIMES_ROOT/zig/zig" c++ "\$@"
EOF
            cp "$RUNTIMES_ROOT/c/bin/clang" "$RUNTIMES_ROOT/c/bin/gcc"
            cp "$RUNTIMES_ROOT/cpp/bin/clang++" "$RUNTIMES_ROOT/cpp/bin/g++"
            chmod +x "$RUNTIMES_ROOT/c/bin/clang" "$RUNTIMES_ROOT/c/bin/gcc" "$RUNTIMES_ROOT/cpp/bin/clang++" "$RUNTIMES_ROOT/cpp/bin/g++"
            ln -sf "$RUNTIMES_ROOT/zig/zig" "$RUNTIMES_ROOT/c/bin/zig" 2>/dev/null || true
            echo -e "  ${GREEN}✓${RESET} Portable C / C++ Compiler ready"
        fi
    else
        echo -e "  ${GREEN}✓${RESET} C / C++ Compiler ready"
    fi

    # 8. Rust (rustc + cargo)
    if [ ! -x "$HOME/.cargo/bin/rustc" ] && [ ! -x "$RUNTIMES_ROOT/rust/bin/rustc" ] && ! command -v rustc >/dev/null 2>&1; then
        echo -e "${CYAN}→${RESET} Installing portable ${BOLD}Rust Toolchain${RESET}..."
        local rust_target="x86_64-apple-darwin"
        if [ "$is_arm" = true ]; then rust_target="aarch64-apple-darwin"; fi
        local rust_url="https://static.rust-lang.org/rustup/dist/${rust_target}/rustup-init"
        if curl -fsSL --retry 2 "$rust_url" -o "$DOWNLOAD_TMP/rustup-init"; then
            chmod +x "$DOWNLOAD_TMP/rustup-init"
            mkdir -p "$RUNTIMES_ROOT/rust/bin"
            RUSTUP_HOME="$RUNTIMES_ROOT/rust/rustup" CARGO_HOME="$RUNTIMES_ROOT/rust/cargo" \
                "$DOWNLOAD_TMP/rustup-init" -y --no-modify-path --default-toolchain stable --profile minimal >/dev/null 2>&1 || true
            ln -sf "$RUNTIMES_ROOT/rust/cargo/bin/rustc" "$RUNTIMES_ROOT/rust/bin/rustc" 2>/dev/null || true
            ln -sf "$RUNTIMES_ROOT/rust/cargo/bin/cargo" "$RUNTIMES_ROOT/rust/bin/cargo" 2>/dev/null || true
            echo -e "  ${GREEN}✓${RESET} Rust ready: $($RUNTIMES_ROOT/rust/bin/rustc --version 2>/dev/null || echo 'stable')"
        fi
    else
        echo -e "  ${GREEN}✓${RESET} Rust already installed"
    fi

    rm -rf "$DOWNLOAD_TMP"
    xattr -dr com.apple.quarantine "$RUNTIMES_ROOT" 2>/dev/null || true
}

if [ "$SKIP_RUNTIMES" = false ]; then
    install_portable_runtimes
fi

# ═══════════════════════════════════════════════════════════════════════════
# Phase 3: Install CLI Launcher ('microcode')
# ═══════════════════════════════════════════════════════════════════════════
CLI_INSTALLED=false
WRAPPER_CONTENT='#!/bin/sh
if [ $# -eq 0 ]; then
    open -a "'"${TARGET_DIR}/MicroCode.app"'"
else
    open -a "'"${TARGET_DIR}/MicroCode.app"'" --args "$@"
fi
'

if [ -w "/usr/local/bin" ]; then
    echo "$WRAPPER_CONTENT" > /usr/local/bin/microcode
    chmod +x /usr/local/bin/microcode
    CLI_INSTALLED=true
    CLI_PATH="/usr/local/bin/microcode"
elif [ -d "$HOME/.local/bin" ] || mkdir -p "$HOME/.local/bin" 2>/dev/null; then
    echo "$WRAPPER_CONTENT" > "$HOME/.local/bin/microcode"
    chmod +x "$HOME/.local/bin/microcode"
    CLI_INSTALLED=true
    CLI_PATH="$HOME/.local/bin/microcode"
fi

echo -e "\n${GREEN}${BOLD}✓ Installation Complete!${RESET}"
if [ -d "${TARGET_DIR}/MicroCode.app" ]; then
    echo -e "${GREEN}✓${RESET} MicroCode installed at: ${BOLD}${TARGET_DIR}/MicroCode.app${RESET}"
fi
echo -e "${GREEN}✓${RESET} Portable Polyglot Runtimes installed at: ${BOLD}${RUNTIMES_ROOT}${RESET}"
if [ "$CLI_INSTALLED" = true ]; then
    echo -e "${GREEN}✓${RESET} CLI command installed: ${CYAN}${CLI_PATH}${RESET} (use: ${BOLD}microcode .${RESET})"
fi

if [ "$RUNTIMES_ONLY" = false ] && [ -d "${TARGET_DIR}/MicroCode.app" ]; then
    echo -e "\n${CYAN}→${RESET} Launching MicroCode..."
    open -a "${TARGET_DIR}/MicroCode.app" || true
fi
echo -e "${GREEN}${BOLD}Welcome to Thailand's 1st IDE!${RESET}\n"
