#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  MicroCode Runtime Bundler v3.0                             ║
# ║  Downloads portable runtimes into the app bundle            ║
# ║  Runs on CI/CD — NOT on developer machines                  ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

APP_BUNDLE="${1}"
TARGET_ARCH="${2:-arm64}"  # "arm64" or "x86_64"

if [ -z "$APP_BUNDLE" ]; then
    echo "Usage: ./bundle_runtimes.sh <AppBundlePath> [Architecture]"
    echo "  Architecture: arm64 (default) or x86_64"
    exit 1
fi

RUNTIMES_ROOT="${APP_BUNDLE}/Contents/Resources/RuntimeLib"
CACHE_DIR=".runtime_cache"

echo "╔══════════════════════════════════════════╗"
echo "║  MicroCode Runtime Bundler v3.0          ║"
echo "║  Arch: ${TARGET_ARCH}                          ║"
echo "╚══════════════════════════════════════════╝"
echo ""

mkdir -p "${RUNTIMES_ROOT}" "${CACHE_DIR}"

download_cached() {
    local url="$1" cache="$2"
    if [ ! -f "$cache" ]; then
        echo "      ↓ Downloading..."
        curl -fSL -o "$cache" "$url" --progress-bar
    else
        echo "      ✓ Cached"
    fi
}

# ─────────────────────────────────────────────
# Node.js v22 LTS
# ─────────────────────────────────────────────
bundle_nodejs() {
    echo "📦 Node.js v22.x LTS..."
    local ver="22.14.0"
    if [ "$TARGET_ARCH" = "arm64" ]; then
        local url="https://nodejs.org/dist/v${ver}/node-v${ver}-darwin-arm64.tar.gz"
    else
        local url="https://nodejs.org/dist/v${ver}/node-v${ver}-darwin-x64.tar.gz"
    fi
    local cache="${CACHE_DIR}/nodejs-${TARGET_ARCH}.tar.gz"
    download_cached "$url" "$cache"
    
    local target="${RUNTIMES_ROOT}/nodejs"
    rm -rf "$target" && mkdir -p "$target"
    tar -xzf "$cache" -C "$target" --strip-components=1
    
    # Trim docs/man to save space
    rm -rf "$target/share" "$target/CHANGELOG.md" "$target/README.md"
    echo "      ✅ $(${target}/bin/node --version 2>/dev/null || echo 'v22.x')"
}

# ─────────────────────────────────────────────
# Python 3.12 (standalone)
# ─────────────────────────────────────────────
bundle_python() {
    echo "📦 Python 3.12..."
    local tag="20241016"
    local ver="3.12.7"
    if [ "$TARGET_ARCH" = "arm64" ]; then
        local url="https://github.com/indygreg/python-build-standalone/releases/download/${tag}/cpython-${ver}+${tag}-aarch64-apple-darwin-install_only.tar.gz"
    else
        local url="https://github.com/indygreg/python-build-standalone/releases/download/${tag}/cpython-${ver}+${tag}-x86_64-apple-darwin-install_only.tar.gz"
    fi
    local cache="${CACHE_DIR}/python-${TARGET_ARCH}.tar.gz"
    download_cached "$url" "$cache"
    
    local target="${RUNTIMES_ROOT}/python"
    rm -rf "$target" && mkdir -p "$target"
    tar -xzf "$cache" -C "$target" --strip-components=1
    
    # Trim test suites & idle
    rm -rf "$target/share" "$target/lib/python3.12/test" "$target/lib/python3.12/idlelib"
    echo "      ✅ $(${target}/bin/python3 --version 2>/dev/null || echo '3.12.x')"
}

# ─────────────────────────────────────────────
# Go 1.23
# ─────────────────────────────────────────────
bundle_go() {
    echo "📦 Go 1.23..."
    local ver="1.23.4"
    if [ "$TARGET_ARCH" = "arm64" ]; then
        local url="https://go.dev/dl/go${ver}.darwin-arm64.tar.gz"
    else
        local url="https://go.dev/dl/go${ver}.darwin-amd64.tar.gz"
    fi
    local cache="${CACHE_DIR}/go-${TARGET_ARCH}.tar.gz"
    download_cached "$url" "$cache"
    
    local target="${RUNTIMES_ROOT}/go"
    rm -rf "$target" && mkdir -p "$target"
    tar -xzf "$cache" -C "$target" --strip-components=1
    
    rm -rf "$target/doc" "$target/test" "$target/api"
    echo "      ✅ $(${target}/bin/go version 2>/dev/null | head -1 || echo 'go1.23.x')"
}

# ─────────────────────────────────────────────
# Deno (TypeScript/JS runtime)
# ─────────────────────────────────────────────
bundle_deno() {
    echo "📦 Deno..."
    if [ "$TARGET_ARCH" = "arm64" ]; then
        local url="https://github.com/denoland/deno/releases/latest/download/deno-aarch64-apple-darwin.zip"
    else
        local url="https://github.com/denoland/deno/releases/latest/download/deno-x86_64-apple-darwin.zip"
    fi
    local cache="${CACHE_DIR}/deno-${TARGET_ARCH}.zip"
    download_cached "$url" "$cache"
    
    local target="${RUNTIMES_ROOT}/deno"
    rm -rf "$target" && mkdir -p "$target/bin"
    unzip -qo "$cache" -d "$target/bin"
    chmod +x "$target/bin/deno"
    echo "      ✅ $(${target}/bin/deno --version 2>/dev/null | head -1 || echo 'latest')"
}

# ─────────────────────────────────────────────
# Bun (fast JS runtime)
# ─────────────────────────────────────────────
bundle_bun() {
    echo "📦 Bun..."
    if [ "$TARGET_ARCH" = "arm64" ]; then
        local url="https://github.com/oven-sh/bun/releases/latest/download/bun-darwin-aarch64.zip"
    else
        local url="https://github.com/oven-sh/bun/releases/latest/download/bun-darwin-x64.zip"
    fi
    local cache="${CACHE_DIR}/bun-${TARGET_ARCH}.zip"
    download_cached "$url" "$cache"
    
    local target="${RUNTIMES_ROOT}/bun"
    rm -rf "$target" && mkdir -p "$target/bin"
    unzip -qo "$cache" -d "$target"
    # Bun extracts into a subfolder
    find "$target" -name "bun" -type f -exec mv {} "$target/bin/bun" \;
    chmod +x "$target/bin/bun" 2>/dev/null || true
    echo "      ✅ $(${target}/bin/bun --version 2>/dev/null || echo 'latest')"
}

# ─────────────────────────────────────────────
# Swift toolchain (uses system Xcode)
# ─────────────────────────────────────────────
bundle_swift_note() {
    echo "📦 Swift — uses system Xcode (no download needed)"
    echo "      ✅ $(swift --version 2>/dev/null | head -1 || echo 'system')"
}

# ─────────────────────────────────────────────
# Rust (rustc + cargo via rustup-init)
# ─────────────────────────────────────────────
bundle_rust() {
    echo "📦 Rust..."
    if [ "$TARGET_ARCH" = "arm64" ]; then
        local url="https://static.rust-lang.org/rustup/dist/aarch64-apple-darwin/rustup-init"
    else
        local url="https://static.rust-lang.org/rustup/dist/x86_64-apple-darwin/rustup-init"
    fi
    local cache="${CACHE_DIR}/rustup-init-${TARGET_ARCH}"
    download_cached "$url" "$cache"
    
    local target="${RUNTIMES_ROOT}/rust"
    rm -rf "$target" && mkdir -p "$target/bin"
    cp "$cache" "$target/bin/rustup-init"
    chmod +x "$target/bin/rustup-init"
    
    # Install minimal toolchain into our bundle dir
    RUSTUP_HOME="$target/rustup" CARGO_HOME="$target/cargo" \
        "$target/bin/rustup-init" -y --no-modify-path --default-toolchain stable \
        --profile minimal 2>/dev/null || true
    
    # Symlink key binaries
    ln -sf "$target/cargo/bin/rustc" "$target/bin/rustc" 2>/dev/null || true
    ln -sf "$target/cargo/bin/cargo" "$target/bin/cargo" 2>/dev/null || true
    
    echo "      ✅ $(${target}/bin/rustc --version 2>/dev/null || echo 'stable')"
}

# ─────────────────────────────────────────────
# Ruby (uses system ruby, just verify)
# ─────────────────────────────────────────────
bundle_ruby_note() {
    echo "📦 Ruby — uses system ruby"
    echo "      ✅ $(ruby --version 2>/dev/null | head -1 || echo 'system')"
}

# ─────────────────────────────────────────────
# Java (Eclipse Temurin JDK 21)
# ─────────────────────────────────────────────
bundle_java() {
    echo "📦 Java (Temurin JDK 21)..."
    if [ "$TARGET_ARCH" = "arm64" ]; then
        local url="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jre_aarch64_mac_hotspot_21.0.5_11.tar.gz"
    else
        local url="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jre_x64_mac_hotspot_21.0.5_11.tar.gz"
    fi
    local cache="${CACHE_DIR}/java-${TARGET_ARCH}.tar.gz"
    download_cached "$url" "$cache"
    
    local target="${RUNTIMES_ROOT}/java"
    rm -rf "$target" && mkdir -p "$target"
    tar -xzf "$cache" -C "$target" --strip-components=1
    
    # Remove unnecessary files
    rm -rf "$target/man" "$target/legal"
    echo "      ✅ $(${target}/bin/java -version 2>&1 | head -1 || echo 'JDK 21')"
}

# ═══════════════════════════════════════════
# Main
# ═══════════════════════════════════════════
main() {
    echo ""
    
    bundle_nodejs
    bundle_python
    bundle_go
    bundle_deno
    bundle_bun
    bundle_swift_note
    bundle_rust
    bundle_ruby_note
    bundle_java
    
    echo ""
    echo "═══════════════════════════════════════"
    echo "📊 Bundle Sizes:"
    echo "═══════════════════════════════════════"
    du -sh "${RUNTIMES_ROOT}"/* 2>/dev/null | sort -rh || true
    echo "───────────────────────────────────────"
    echo "📦 Total: $(du -sh "${RUNTIMES_ROOT}" | cut -f1)"
    echo ""
    echo "✅ All runtimes bundled for ${TARGET_ARCH}!"
}

main
