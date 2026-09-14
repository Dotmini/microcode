# Building MicroCode from Source

This guide provides comprehensive, step-by-step instructions for building **MicroCode** from source on macOS.

---

## 1. System Requirements & Prerequisites

| Requirement | Minimum Version | Recommended | Purpose |
| :--- | :--- | :--- | :--- |
| **macOS** | 13.0 (Ventura) | 14.0+ (Sonoma) / 15.0+ (Sequoia) | Operating System |
| **Architecture** | Apple Silicon (arm64) | M1 / M2 / M3 / M4 / M5 | Native Metal acceleration |
| **Xcode & CLT** | 15.0+ | Latest Xcode | Swift 5.9+, AppKit & Metal toolchains |
| **Rust & Cargo** | 1.75.0+ | Latest stable (`rustup`) | Backend engine, FFI static libraries |
| **Node.js** | 18.0+ | LTS (v20+) | VS Code extension compatibility host |

### Installation of Prerequisites

```bash
# 1. Install Xcode Command Line Tools
xcode-select --install

# 2. Install Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# 3. Ensure Node.js & TypeScript are available
node --version
npm --version
```

---

## 2. Architecture Overview

MicroCode consists of four tightly-coupled components:
1. **SwiftUI / AppKit Frontend** (`MicroCode/`): Native macOS interface with Metal GPU rendering.
2. **Rust Core FFI Library** (`microcode_core/`): High-performance native memory, syntax, and diff engine compiled as `libmicrocode_core.a`.
3. **Rust Embedded FFI Library** (`backend/`): Sandboxed execution, ACP protocol, and agent harness compiled as `libmicrocode_embedded.a`.
4. **VS Code Compatibility Host** (`vscode-compat-host/`): Isolated TypeScript runtime implementing the VS Code extension API.

---

## 3. The Primary Build Script: `build.sh`

The root [`build.sh`](./build.sh) script is the recommended and authoritative way to build MicroCode. It coordinates Cargo, Swift Package Manager, and bundle packaging.

### Common Usage Modes

#### A. Full Production Release Build (Default)
Builds all Rust FFI libraries, compiles the VS Code compatibility host, compiles the SwiftUI frontend in Release mode, and packages `MicroCode.app`:
```bash
./build.sh
```

#### B. Fast Frontend-Only Build (`--frontend-only`)
When you are modifying Swift files or UI views and the Rust FFI static libraries have already been compiled, use `--frontend-only` to skip Cargo compilation:
```bash
./build.sh --frontend-only
```
*Time: ~30-60 seconds instead of several minutes.*

#### C. Backend-Only Build (`--backend-only`)
Compiles only the Rust Axum backend server and CLI tools:
```bash
./build.sh --backend-only
```

#### D. Debug Build (`--debug`)
Builds both backend and frontend in debug mode with faster compile times and full debugging symbols:
```bash
./build.sh --debug
```

#### E. Clean Rebuild (`--clean`)
Cleans Cargo and SwiftPM intermediate caches before initiating the build:
```bash
./build.sh --clean
```

#### F. External SSD Cache Offloading (`--external-ssd`)
For maintainers or power developers with limited internal storage:
```bash
./build.sh --external-ssd
```
Offloads Cargo crate registries, build targets, DerivedData, and SwiftPM scratch files to a mounted external APFS volume (`/Volumes/MicroCodeBuild` or `/Volumes/MAC/CodeTunerBuild`), preserving internal SSD lifespan and disk space.

---

## 4. Build Root Modes (Local vs. External SSD)

MicroCode separates build environments cleanly between standard contributors and power maintainers:

### Standard Contributor Mode (Default)
- Running `./build.sh` without flags builds **100% locally** on your internal drive in `./.build/`.
- Uses your existing `~/.cargo` and `~/.rustup` caches naturally, without redownloading dependencies.
- No external drive required or checked.

### External SSD / Custom Volume Mode (Opt-in)
To offload intermediate artifacts or redirect build files to an external SSD:
```bash
# Option 1: Use the --external-ssd flag
./build.sh --external-ssd

# Option 2: Specify a custom build directory
./build.sh --build-root /Volumes/MySSD/MicroCodeBuild

# Option 3: Set the environment variable
export CODETUNER_BUILD_ROOT="/Volumes/MySSD/MicroCodeBuild"
./build.sh
```

---

## 5. Developer Iterative Script: `build_dev.sh`

For rapid day-to-day development of SwiftUI components, [`build_dev.sh`](./build_dev.sh) compiles the debug binary and bundles it directly into `$HOME/Applications/MicroCode.app`:

```bash
./build_dev.sh
```

### Options
- `--with-runtimes`: Downloads and bundles isolated Node.js, Python, and Go runtimes into the `.app` bundle.

---

## 6. Distribution Packaging: `build_distribution.sh`

To generate distributable disk images (`.dmg`) and installer packages (`.pkg`):

```bash
# Build universal binary release DMG and PKG
./build_distribution.sh

# Fast debug distribution build
./build_distribution.sh --dev

# Build, sign, and notarize with Apple Developer ID
./build_distribution.sh --sign
```

---

## 7. Cleaning & Disk Space Recovery

To clean intermediate build products across Rust, Swift, and Xcode:
```bash
./clean_project.sh
```

---

## 8. Codesigning & Permissions

On macOS, running local builds that require accessibility, terminal PTY, or simulator capture requires ad-hoc signing:

```bash
codesign --force --deep --sign - /path/to/MicroCode.app
```

---

## 9. Troubleshooting

### 1. `ld: library not found for -lmicrocode_embedded` or `-lmicrocode_core`
Run a full build once (`./build.sh`) or manually build the Rust libraries:
```bash
cargo build --manifest-path backend/Cargo.toml --release
cargo build --manifest-path microcode_core/Cargo.toml --release
```

### 2. AppleDouble (`._*`) errors on non-APFS drives
If building on FAT32/exFAT drives, extended attributes can cause compilation issues. The build script automatically cleans them, or you can run:
```bash
find . -name "._*" -delete
```

### 3. Missing `tsc` for VS Code Compatibility Host
Ensure dependencies are installed in `vscode-compat-host`:
```bash
cd vscode-compat-host && npm install && cd ..
```
