# Authentic Native GUI Architecture

This directory contains the cross-platform GUI architecture for CodeTunner.

## Structure

- **Common/**: Shared C++ interfaces and types that define the contract for the GUI.
- **Platforms/**: Platform-specific implementations.
  - **Linux/**: Code for GTK/Qt integration.
  - **Windows/**: Code for WinUI/Win32 integration.
  - **macOS/**: Reference to the native AppKit implementation (located in `CodeTunner/`).

## Philosophy

The core logic (AI, Syntax, Indexing) resides in the `backend/` (Rust) or `CodeTunnerSupport/` (ObjC++). The GUI layer is a thin presentation layer that consumes these services.
