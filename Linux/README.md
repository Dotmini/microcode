# CodeTunner for Linux

This directory contains the Swift bridging and execution layer for the Linux platform.

## Architecture
- **Rust Backend**: Reuses the core logic from `../backend` and `../microcode_core` compiled as `.so` (Shared Objects).
- **Swift Logic**: Reuses non-UI Swift services (LSP, Git, AI Client) that are compatible with Swift on Linux.
- **UI Framework**: To be determined (e.g., GTK+ via Swift-GNOME, or headless background service).

## Build Preparation
1. Compile the Rust components for Linux target:
   ```bash
   cd ../backend
   cargo build --release --target x86_64-unknown-linux-gnu
   ```
2. Link the generated `libcodetunner_embedded.so` and `libmicrocode_core.so` via SPM or Make.
3. Build the Swift executable:
   ```bash
   swift build -c release
   ```
