# CodeTunner for Windows

This directory contains the Swift bridging and execution layer for the Windows platform.

## Architecture

- **Rust Backend**: Reuses the core logic from `../backend` and `../microcode_core` compiled as `.dll` (Dynamic Link Library).
- **Swift Logic**: Reuses non-UI Swift services (LSP, Git, AI Client) that are compatible with Swift on Windows (via Windows Toolchain).
- **UI Framework**: To be determined (e.g., WinUI 3, SwiftWin32, or headless background service).

## Build Preparation

1. Compile the Rust components for Windows target:

   ```cmd
   cd ../backend
   cargo build --release --target x86_64-pc-windows-msvc
   ```

2. Link the generated `codetunner_embedded.dll` and `microcode_core.dll` via SPM.
3. Build the Swift executable using the Windows Swift Toolchain:

   ```cmd
   swift build -c release
   ```
