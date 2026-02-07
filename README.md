MICROCODE NATIVE --- HIGH-PERFORMANCE macOS IDE

Repository: https://github.com/XevilA/microcode/

----------------------------------------------------------------------

HEADER

----------------------------------------------------------------------

TIRAWAT NANTAMAS | FOUNDER OF DOTMINI SOFTWARE & SPU AI CLUB

PROGRAM: MAJOR (INTERDISCIPLINARY TECHNOLOGY AND INNOVATION)

PROJECT: MICROCODE NATIVE ENGINE

----------------------------------------------------------------------

OVERVIEW

----------------------------------------------------------------------

MicroCode Native is a high-performance Integrated Development Environment (IDE) engineered for modern software engineering workflows. The system combines:

- Native macOS user interface (SwiftUI with AppKit integration)

- Rust-based asynchronous backend services

- Objective-C++ core for performance-critical subsystems

Primary objectives:

- Native responsiveness with GPU-accelerated rendering (Metal)

- Deterministic performance for large repositories and long sessions

- Safe and scalable concurrency using Rust async patterns

- Extensibility with strong isolation using WebAssembly sandboxing

----------------------------------------------------------------------

KEY CAPABILITIES

----------------------------------------------------------------------

1) Hybrid Native Architecture

- Frontend: SwiftUI + AppKit interoperability for native macOS controls and interaction

- Core Kernel: Objective-C++ modules for low-level performance and text pipeline efficiency

- Backend Services: Rust (Axum/Tokio) for concurrency, orchestration, and system services

2) AI Integration (AI-First Workflow)

- Integrated support for AI providers in the Gemini / OpenAI / Claude class

- Intended use cases:

  - Assisted refactoring and code transformation

  - Semantic explanations and project-aware guidance

  - Context-aware completion aligned to project intent

3) WASM Extension System

- Modular extension architecture using a Wasmtime-based host

- Goals:

  - Near-native execution speed

  - Strict sandbox boundaries

  - Controlled capability exposure for security and stability

4) Playground Cell Mode

- Multi-block execution environment designed for experimentation and repeatable workflows

- Includes categorized execution logic (e.g., run-grouping policies) and snippet catalog management

5) Native macOS Performance UI Components

- AuthenticFileTree: high-speed file navigation aligned with native AppKit patterns (e.g., NSOutlineView-style)

- AuthenticTerminal: integrated PTY terminal for direct CLI workflows

- GPU-rendered visual effects for smooth rendering and consistent frame pacing

----------------------------------------------------------------------

REPOSITORY STRUCTURE (HIGH-LEVEL)

----------------------------------------------------------------------

This repository contains multiple modules and build utilities. Typical top-level components include:

- GUI/

- backend/

- extension-host/

- microcode_core/

- vscode-compat-host/

- build and signing scripts

Reference documents commonly included:

- QUICKSTART.txt (or QUICKSTART.md in the repo)

- PROJECT_STRUCTURE.txt (or PROJECT_STRUCTURE.md)

- PROJECT_SUMMARY.txt (or PROJECT_SUMMARY.md)

- SIGNING_GUIDE.txt (or SIGNING_GUIDE.md)

Note:

If any legacy naming remains in folders/files, it should be treated as historical naming pending migration. Prefer "MicroCode" as the official product name.

----------------------------------------------------------------------

REQUIREMENTS

----------------------------------------------------------------------

- macOS 13.0+

- Xcode 15.0+

- Rust 1.70+

- Node.js 18.0+

----------------------------------------------------------------------

BUILD

----------------------------------------------------------------------

1) Clone

Command:

  git clone https://github.com/XevilA/microcode.git

  cd microcode

2) Developer Build (Debug)

Command:

  ./build.sh --debug

3) Production Build (Release)

Command:

  ./build.sh --release

4) Modular Build Options

Commands:

  ./build.sh --backend-only

  ./build.sh --frontend-only

  ./build.sh --clean

Additional build/distribution/signing scripts may exist, for example:

- build_distribution.sh

- build_extensions.sh

- bundle_runtimes.sh

- sign_and_notarize.sh

- verify_checksums.sh

Operational note:

If script flags differ across branches, treat the local build scripts as the source of truth.

----------------------------------------------------------------------

ARCHITECTURE OVERVIEW

----------------------------------------------------------------------

- macOS App (SwiftUI) communicates with:

  - Language Core (Objective-C++)

  - Backend Server (Rust)

- Backend Server provides:

  - AI Engine integration

  - WASM Extension Host

  - Git Manager

- Language Core provides:

  - Lexing, highlighting, and performance-critical text operations

----------------------------------------------------------------------

CREDITS AND LEADERSHIP

----------------------------------------------------------------------

- Tirawat Nantamas --- Lead Architect and Project Owner (Dotmini Software)

- SPU AI CLUB, Sripatum University (มหาวิทยาลัยศรีปทุม) --- Research and community collaboration

----------------------------------------------------------------------

LICENSE

----------------------------------------------------------------------

Elite Commercial License --- Dotmini Software

Use is governed by commercial licensing terms.

----------------------------------------------------------------------

END OF FILE

----------------------------------------------------------------------
