## Support the Project

MicroCode is built and maintained by Dotmini Company Limited. If this project saves you time or inspires your work, consider supporting continued development.

### PromptPay / Bank Transfer

| | |
|---|---|
| **Bank** | Krungthai Bank (ธนาคารกรุงไทย) |
| **Account** | 460-0-70494-0 |
| **Name** | นายถิรวัฒน์ นันตมาศ |

> PromptPay QR available upon request.

### GitHub Sponsors

If you prefer recurring support or wish to appear in the official sponsors list:

[![Sponsor on GitHub](https://img.shields.io/badge/Sponsor-GitHub_Sponsors-EA4AAA?style=flat-square&logo=github-sponsors&logoColor=white)](https://github.com/sponsors/Dotmini)

Every contribution directly funds engineering time, Apple Developer infrastructure, and GPU compute resources.

---


<p align="center">
  <img src="MicroCOdeDoogleIcon.png" alt="MicroCode" width="420" />
</p>

<h1 align="center">MicroCode</h1>

<p align="center">
  <strong>The Native AI-Powered IDE for macOS</strong><br/>
  <em>Built from scratch. No Electron. No compromises.</em>
</p>

<p align="center">
  <a href="https://microcode.dotmini.net"><img src="https://img.shields.io/badge/Official_Website-microcode.dotmini.net-007AFF?style=flat-square&logo=safari&logoColor=white" alt="Official Website" /></a>
  <img src="https://img.shields.io/badge/Platform-macOS_13+-black?style=flat-square&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/Rust-1.75+-DEA584?style=flat-square&logo=rust&logoColor=white" />
  <img src="https://img.shields.io/badge/Metal-GPU_Accelerated-8E8E93?style=flat-square&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/License-Elastic_License_2.0-blue?style=flat-square" />
  <img src="https://img.shields.io/github/actions/workflow/status/Dotmini/microcode/ci.yml?style=flat-square&logo=githubactions&logoColor=white&label=CI/CD" alt="Build Status" />
  <img src="https://img.shields.io/github/v/release/Dotmini/microcode?style=flat-square&color=green" />
</p>

<p align="center">
  <a href="https://microcode.dotmini.net"><strong>🌐 Official Website</strong></a> ·
  <a href="https://github.com/Dotmini/microcode/releases/tag/v2.5.40"><strong>Download v2.5.40 (Latest Release)</strong></a> ·
  <a href="#whats-new-in-v2540"><strong>What's New in v2.5.40</strong></a> ·
  <a href="#operational-modes"><strong>Operational Modes</strong></a> ·
  <a href="#core-engineering-specifications"><strong>Features</strong></a> ·
  <a href="#architecture"><strong>Architecture</strong></a> ·
  <a href="#getting-started"><strong>Getting Started</strong></a>
</p>

---

## Why MicroCode?

Every modern IDE is built on Electron — a web browser pretending to be a native app. **MicroCode is different.**

We built a **fully native macOS IDE from scratch** using SwiftUI, Rust, and Metal. The result is an editor that launches in under a second, uses a fraction of the memory, and feels like it belongs on your Mac.

| | MicroCode | Electron IDEs |
|---|---|---|
| **Startup time** | < 1s | 3-8s |
| **Memory (idle)** | ~80 MB | 400-800 MB |
| **GPU rendering** | Metal (native) | WebGL (emulated) |
| **AI integration** | 7+ Cloud providers + Multi-Node Local LLM Pool, native | Plugin-dependent |
| **Multi-Workspace Agent** | Concurrent parallel execution across workspaces | Single-window / blocking |
| **File indexing** | Tree-sitter + Rust | JS-based |

---

## What's New in v2.5.41

### 1. Subscription and BYOK are fully isolated
- **Two credential stores, never mixed.** Web Subscription credentials live only in `km_sealed_sub_<provider>`; BYOK keys live only in `<provider>_api_key`. Subscription mode never reads, writes or bills a BYOK key, and BYOK mode never borrows a Subscription login or a CLI session. Cross-provider failover now happens only inside the active mode.
- **CLI bridges no longer inherit shell API keys.** `claude`, `codex` and `gemini` run with `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY` and `GOOGLE_API_KEY` removed, so a subscription turn cannot silently bill an API key.
- **Enterprise Vertex / custom-gateway overrides can no longer hijack a Subscription turn** (this was why Google AI Ultra returned 401 on machines with Vertex enabled).

### 2. Subscription reliability
- **ChatGPT / Codex**: expired `~/.codex/auth.json` tokens refresh automatically (with one retry on 401); account id is read from the JWT; every real Codex model slug is accepted.
- **Claude**: only a real Pro / Max / Team login (`claude auth status` reports a `subscriptionType`) counts as a Subscription. A prepaid Console org with no credit is rejected instead of streaming "Credit balance is too low" as the answer. Anthropic OAuth tokens use the correct headers. `claude.ai` web sessions are supported through `ClaudeWebSessionBridge`.
- **Gemini**: official browser OAuth (loopback PKCE) replaces unusable web cookies.
- **GLM** uses the Coding Plan endpoint with automatic Z.AI / BigModel region fallback; Subscription routes ignore the BYOK custom base URL.
- **Settings → AI → Subscription → Test connections** sends a one-line probe through each Subscription route and shows why a login does not work (not connected, expired, no credit or plan, wrong model, provider down).

### 3. Built-in skills and a harness baseline
- Ten skills ship inside the app: four from Anthropic's `anthropics/skills` (Apache-2.0, unmodified, with their licences: `frontend-design`, `webapp-testing`, `mcp-builder`, `theme-factory`) and six of ours (`microcode-harness-core`, `microcode-anti-slop`, `microcode-swift-macos-ui`, `microcode-thai-ui-typography`, `microcode-security-baseline`, `microcode-skill-authoring`). Provenance is in `MicroCode/Resources/BuiltinSkills/NOTICE.md`.
- The harness protocol and the anti-slop bar are injected into every agent and sub-agent turn; the rest load by intent.
- New `slop_check` tool: a deterministic linter for filler prose, placeholder code, empty `catch`, default-template UI tells and hard-coded secrets.

### 4. Dotmini Cloud purchase flow
- "Top Up / Plans", "Sign In" and the Cloud menu's upgrade item opened the Cloud GPU page; they now open **Account & License**.
- Email sign-up and password reset are available in the app.
- After opening Beam Checkout the app confirms the payment automatically and offers "Use Dotmini Cloud AI now".
- The offline cloud model list only contains models the gateway really serves.

### 5. MicroCode AI ships from this repository
- `MicroCode AI` (standalone, AI-agent edition) is now built from the same commit and published in the same release as MicroCode (`package_ai_from_lite.sh`).

## What's New in v2.5.40

### 1. AI Agent as a Real-Time Teammate in Collaboration Mode (`MicroCode AI` + Follow Mode)
- **Live AI Participant (Collab-Only Activation)**: Exclusively when a Collaboration session is active (`isCollabSessionActive`), **`MicroCode AI`** (`role: "AI Agent"`, `#A855F7`) joins the room as a real-time teammate. Normal single-user IDE usage outside Collab remains completely untouched with zero overhead.
- **Real-Time Cursor, Line-Range & Buffer Sync**: Every time the AI Agent reads, searches, or edits files (`file_read`, `replace_in_file`, `multi_replace_in_file`, `file_write`, `patch_file`), its live cursor position, modified line range (`line`..`endLine`), active tool status, and updated file contents are broadcast over WebSockets in real time.
- **1-Click Follow Mode (`Follow AI` / `Follow Peer`)**: Both **Native macOS IDE** users and **WebApp Collaboration Portal** teammates can click **Follow AI** (or follow any human peer). Your editor automatically switches files and scrolls smoothly to the exact line the AI Agent is inspecting or modifying in real time.
- **`@ai` Team Chat Dispatch**: Mention `@ai` (or click the `@ai` quick button) inside **Session Chat** from either the WebApp browser portal or the Native IDE to assign tasks to the AI Agent and receive its response directly in the shared team chat.

### 2. WebApp Collaboration Portal: Vector SVG Icons & Syntax Highlighting
- **Authentic File & Folder SVG Icons**: Replaced generic monochrome placeholders with color-coded vector SVG icons across the Workspace File Tree and Editor Tab Bar (`.tsx`/`.jsx`, `.ts`, `.js`, `.css`, `.html`, `.json`, `.swift`, `.py`, `.rs`, `.md`, images, audio, and folder types).
- **Live Syntax Color Highlighting & Collaborator Overlay**: Upgraded the browser editor with a synchronized line-number gutter (`#lineGutter`), single-pass syntax color highlighting (`#codeHighlightContent`), and in-editor collaborator line-range highlight strips with floating cursor badges (`#editorCollabOverlay`).

### 3. Concurrent Multi-Workspace AI Agent Execution
- **Parallel Per-Workspace Agent Slots**: Each workspace and conversation runs inside an isolated `WorkspaceExecutionContext`. Multiple AI Agents can plan, edit files, and run builds/commands across multiple workspaces simultaneously without blocking the UI or mixing workspace paths.
- **Live Background Workspace Indicators**: The sidebar displays per-workspace spinning indicators when background agents are active and completion badges when background runs finish.

### 4. Multi-Endpoint Local LLM Connection Pool
- **Simultaneous Multi-Node Local LLM Connections**: Register and connect to multiple Local LLM servers at the same time (local Ollama `:11434`, LM Studio `:1234`, vLLM `:8000`, llama.cpp `:8080`, Apple MLX, or remote LAN/Tailscale GPU workstations).
- **Unified Model Pool & Auto-Failover**: Concurrently health-checks all enabled endpoints, aggregates every model into the unified picker (`endpointId::modelId`), routes inference to the exact node that hosts the selected model, and automatically fails over to another online Local LLM node if a server drops.

### 5. Direct Subscription AI Login (Zero API-Key Cost)
- **Use Your Existing AI Subscriptions Directly (`SubscriptionAuthManager` & `LocalSubscriptionGatewayService`)**: Sign in with 1-Click OAuth or embedded browser session to use **ChatGPT Plus / Pro / Team (Codex)**, **Claude Pro / Max**, **Google Gemini Advanced / CodeAssist**, **GitHub Copilot**, **Cursor**, **Qwen**, **Kimi**, and **Zhipu GLM** directly inside MicroCode — without paying extra per-token API fees.
- **Automatic Token Refresh & Multi-Account Failover**: Credentials are stored in the macOS Keychain with background token refresh and automatic fallback across Subscription, BYOK API keys, and Local LLM pools.

### 6. Bidirectional ACP (Agent Client Protocol) — Host, Server & Ghost Text
- **ACP Host (`ACPHostService`)**: Connect external ACP-compatible coding agents (**Claude Code**, **Gemini CLI**, **OpenAI Codex CLI**, **Goose**, or any JSON-RPC 2.0 ACP binary) directly into MicroCode's native UI, streaming timeline, inline diff reviewer, and `⌘↵` permission gate.
- **ACP Server (`ACPServerService`)**: Run MicroCode itself as a standards-compliant ACP Server over `stdio` or WebSocket so external orchestrators and CLI pipelines can invoke MicroCode's native agent and workspace tools.
- **ACP Ghost Text Bridge (`ACPGhostTextBridge`)**: Real-time inline ghost-text code completions streamed directly from ACP agents and active subscription sessions.

### 7. Two-Way Model Context Protocol (MCP Client + Built-In 35-Tool IDE MCP Server)
- **External MCP Client (`ExternalMCPManager`)**: Auto-imports MCP servers from Claude Desktop (`claude_desktop_config.json`), Cursor, or custom `stdio`/SSE endpoints and injects their tools & resources directly into MicroCode's autonomous agent loop.
- **Built-In MicroCode MCP Server (`MCPServer` / `microcode_mcp` / `mcp-server.py`)**: Exposes **35+ native MicroCode IDE tools** over loopback HTTP/SSE and `stdio` — including AST `find_symbol`, `file_read`/`patch_file`, `lsp_intelligence`, `computer_use_*` GUI automation, `device_interact` / `adb_execute` (iOS Sim & Android Emu), `preview_control`, `cell_run`, `ardium_run`, `api_studio`, and `database_studio`.

### 8. Enterprise AI Governance, DLP & Cryptographic Audit Ledger
- **DLP Secret & PII Redaction Gate**: Automatically scans and masks API keys (`sk-*`, `AIza*`, `AKIA*`), Bearer tokens, Private Keys, and PII before any prompt leaves the device, with support for strict **Air-Gapped / Local-Only Mode**.
- **Tamper-Evident SHA-256 Audit Ledger**: Every AI prompt, model call, and tool execution is recorded in a hash-chained JSONL ledger (`enterprise_audit_chain.jsonl`) with one-click integrity verification and compliance export.
- **Spend Caps & Organization Policy (`.microcode-org-policy.json`)**: Enforce daily/monthly USD budget limits, approved provider/model allowlists, and mandatory tool approval gates across engineering teams.

### 9. Native Computer Use, Phone Companion & Portable `.arx` Capsules
- **Vision-Guided Native Computer Use (`NativeComputerUseService`)**: Autonomous screen inspection, element clicking, typing, and keyboard shortcuts across macOS apps and embedded simulators.
- **Phone Companion & QR Local LLM Gateway (`PhoneCompanionService`)**: Scan a QR code from your iPhone or Android to trigger **Build & Run**, approve agent tools, inspect live previews, or chat with your Mac's Local LLMs from your phone.
- **Portable `.arx` Agent Capsules (`ARXCapsuleService`)**: Package and share complete agent threads, implementation plans, and workspace memory snapshots as native `.arx` files.

---

## Operational Modes & Competitive Advantages

MicroCode features a multi-modal workspace architecture where each mode is engineered from the ground up for a specific software engineering discipline. Unlike traditional IDEs and Electron-based wrappers, MicroCode executes every mode natively on Apple Silicon using Metal, Swift, and Rust.

### Comparative Architectural Analysis

| Operational Mode | Primary Functionality | MicroCode Architectural Implementation | Legacy Competitors (VS Code, Cursor, Windsurf, Xcode, JetBrains) |
|:---|:---|:---|:---|
| **Code Editor** | Primary editing & multi-language development | 100% native AppKit `NSTextView` backed by an Objective-C++ gap buffer and Metal GPU font rasterizer. Sub-second cold startup, <80 MB RAM. | Electron webviews (400–1200 MB RAM idle). Canvas-emulated font rendering prone to JavaScript garbage collection frame drops. |
| **Autonomous AI Agent** | Multi-file refactoring, planning & self-healing | Enforces formal Implementation Plans before touching code. Interactive `⌘↵` tool approval gate. 7 native Tier-1 LLM connections. | Unpredictable file overwrites, blind shell command execution, vendor lock-in with middleman token markups. |
| **Embedded Device Dock** | Mobile & desktop simulation directly in-editor | Low-latency WebSocket H.264 iOS stream (`serve-sim`) and ADB Android mirror (`scrcpy-server`) with 120 FPS Metal device shaders. | External detached emulator windows (Xcode/Android Studio) that cause desktop clutter; non-existent in VS Code/Cursor without laggy webview plugins. |
| **Database Studio** | SQL queries, schema explorer & tabular viewer | Native C and Rust database drivers for PostgreSQL, MySQL, and SQLite. Zero-latency pagination directly in-process. | Heavy Electron plugins (SQLTools) or separate memory-heavy Java applications (DataGrip/DBeaver) taking 1 GB+ RAM. |
| **API Client Studio** | REST & GraphQL request designer and inspector | Native Swift networking engine with environment presets, token injection, and instant formatted JSON/XML inspectors. | Developers must run separate heavy Electron applications (Postman/Insomnia) consuming 800 MB+ RAM. |
| **Notebook & Cell Mode** | Polyglot exploratory computing & step execution | Native multi-runtime engine (Swift, Rust, Python, Ardium) with sub-millisecond dispatch and direct stdio pipe capture. | Jupyter / VS Code Notebooks with fragile Python kernel connections, sluggish web widgets, and connection dropouts. |
| **Playground Mode** | In-memory scratchpad & instant REPL | Memory-backed scratchpad with live AST evaluation and execution profiling without creating disposable disk files. | Xcode Playgrounds frequently stall or crash; VS Code lacks native scratchpad without saving files to disk. |
| **Remote Explorer (Remote X)** | Headless cloud server & container development | Direct POSIX SSH/SFTP over secure Unix sockets with zero daemon installation required on remote target. | VS Code Remote installs a heavy proprietary Node.js server daemon (`vscode-server`) that triggers firewall and RAM issues. |
| **Embed & IoT Studio** | Hardware development & firmware flashing | Native serial port monitor, real-time baud switching, and direct hardware register observation for ESP32/STM32/Pico. | Fragmented between Arduino IDE, Java-based tools, or complex CLI command configurations. |
| **Science Mode** | Computational research & bioinformatics | Specialized pipelines for biological data visualization, structure models, and vector mathematics. | Requires switching across external web dashboards and disparate CLI scientific tools. |
| **Extension Studio** | Extension management & ecosystem customization | Native Open VSX registry integration with an isolated Node.js VS Code compatibility runner; zero Electron overhead. | VS Code proprietary marketplace vendor lock-in and heavy background runtime consumption. |
| **Ardium Toolchain** | Next-gen system programming with Ardium v2.3 | Official native compiler runner, Tree-sitter AST queries, RAII `@owned` ownership linting, and CoreUI live rendering. | Non-existent in third-party IDEs. MicroCode is the flagship workstation for the Ardium programming language. |

---

### Detailed Operational Mode Breakdown

#### 1. Code Editor Mode (`.code`)
- **Purpose**: Engineered for daily high-velocity coding across 30+ languages (Swift, Rust, C/C++, TypeScript, Python, Go, Ardium, and more).
- **Why It Outperforms Competitors**:
  - Eliminates Electron entirely. While VS Code, Cursor, and Windsurf render text within Chromium DOM elements or WebGL canvas layers—triggering micro-stutters during rapid cursor navigation and high battery consumption—MicroCode executes directly against macOS CoreText and Metal.
  - File buffer mutations operate on an optimized Objective-C++ text gap buffer, ensuring zero latency even when opening multi-megabyte source files.

#### 2. Autonomous AI Agent Mode (`.aiAgent`)
- **Purpose**: Autonomous end-to-end task execution, large refactors, test synthesis, and self-directed debugging.
- **Why It Outperforms Competitors**:
  - Competitor agent tools (Cursor Composer, Windsurf Cascade) frequently apply speculative multi-file edits prematurely or execute arbitrary terminal commands without deterministic checks.
  - MicroCode enforces **Formal Implementation Plans**: the agent first reasons through the problem, maps dependencies via the AST RepoMap, and presents a phased plan. Destructive tool invocations (file overwrites, command executions, git operations) are halted at the **`⌘↵` Tool Approval Barrier** until explicitly confirmed by the developer.
  - Direct connection to 7 leading AI providers (Google Gemini 3.1/2.5, Anthropic Claude Opus 4.7/Sonnet 4, OpenAI GPT-5/o3, DeepSeek V4, xAI Grok, Alibaba Qwen, Zhipu GLM) with zero third-party proxy markup or latency penalties.

```mermaid
flowchart LR
    %% Deterministic Agent Execution Flow
    Task(["🎯 <b>User Task Request</b><br/>Multi-Turn Objective"])
    Plan["📋 <b>Implementation Plan</b><br/>AST Tree-sitter & RepoMap"]
    Gate{"🔐 <b>⌘↵ Human Approval</b><br/>Review Destructive Ops"}
    Exec["⚡ <b>Sandboxed Execution</b><br/>File Edit • Shell • Git"]
    Verify{"🧪 <b>Automated Verification</b><br/>Build • Tests • Lints"}
    SelfHeal["🔄 <b>Self-Healing Loop</b><br/>Root Cause Diagnosis"]
    Done(["✅ <b>Verified Complete</b><br/>Clean Working Tree"])

    Task --> Plan
    Plan --> Gate
    Gate -- "Approved (⌘↵)" --> Exec
    Gate -- "Reject / Refine" --> Plan
    Exec --> Verify
    Verify -- "Pass" --> Done
    Verify -- "Fail" --> SelfHeal
    SelfHeal --> Exec

    classDef step fill:#0f172a,stroke:#38bdf8,stroke-width:1.5px,color:#f8fafc;
    classDef gate fill:#312e81,stroke:#a855f7,stroke-width:2px,color:#ffffff;
    classDef action fill:#18181b,stroke:#f97316,stroke-width:1.5px,color:#f8fafc;
    classDef success fill:#064e3b,stroke:#10b981,stroke-width:1.5px,color:#f8fafc;
    classDef loop fill:#451a03,stroke:#f59e0b,stroke-width:1.5px,color:#f8fafc;

    class Task,Plan step;
    class Gate gate;
    class Exec action;
    class Verify gate;
    class SelfHeal loop;
    class Done success;
```

#### 3. Embedded Device Dock Mode (`EmbeddedDeviceDockView`)
- **Purpose**: Unified mobile and desktop application simulation, interactive touch testing, and viewport inspection directly within an editor tab.
- **Why It Outperforms Competitors**:
  - Eliminates the cognitive disruption of managing separate simulator windows. Xcode and Android Studio require external window management that obscures code editor workspaces.
  - MicroCode streams iOS Simulator video frames directly into an editor pane using low-latency WebSocket H.264 via an embedded `serve-sim` daemon, while physical Android devices and emulators mirror over ADB via `scrcpy-server`.
  - Custom Metal shaders render hardware device bezels, glass reflections, and Dynamic Island cutouts at a locked 120 FPS on Apple ProMotion displays.

#### 4. Database Studio Mode (`.database`)
- **Purpose**: Complete SQL workspace for developers managing application data, executing queries, and inspecting relational schemas.
- **Why It Outperforms Competitors**:
  - Replaces third-party database tools (e.g. TablePlus, DBeaver) and unstable VS Code extensions.
  - Compiled native drivers connect directly to PostgreSQL, MySQL, and SQLite instances. Query execution outputs directly into a high-performance native AppKit data grid with instant pagination and schema autocompletion.

#### 5. API Client Studio Mode (`.apiClient`)
- **Purpose**: Comprehensive workbench for designing, testing, and debugging REST and GraphQL APIs.
- **Why It Outperforms Competitors**:
  - Developers no longer need to run heavy Electron clients like Postman or Insomnia (which consume upwards of 800 MB RAM).
  - Offers native environment variable interpolation, authentication token injection (Bearer, OAuth2, API Key), request history persistence, and color-coded JSON/XML tree rendering built directly into the IDE core.

#### 6. Interactive Notebook & Cell Mode (`.notebook`)
- **Purpose**: Granular, cell-by-cell code execution for data exploration, algorithm verification, and documentation.
- **Why It Outperforms Competitors**:
  - Traditional Jupyter notebooks suffer from bloated web interfaces, fragile Python kernel socket drops, and difficulty tracking state.
  - MicroCode provides polyglot cell execution (Swift, Rust, Python, Ardium) running on native Unix processes with real-time output capture and native graphical rendering.

#### 7. Interactive Playground Mode (`.playground`)
- **Purpose**: Instant zero-setup REPL scratchpad for testing algorithms and language syntax.
- **Why It Outperforms Competitors**:
  - Xcode Playgrounds are notorious for compilation deadlocks and simulator crashes. VS Code requires creating manual scratch files on disk.
  - MicroCode runs a memory-backed execution harness with real-time AST tokenization and execution profiling, leaving zero artifact clutter in your repository.

#### 8. Remote Explorer Mode (`.remoteX`)
- **Purpose**: Seamless remote development on cloud VMs, bare-metal servers, and containerized environments.
- **Why It Outperforms Competitors**:
  - VS Code Remote SSH downloads a massive Node.js runtime onto the remote host, causing failures on restricted infrastructure or non-standard Linux distros.
  - MicroCode uses standard, secure POSIX SSH and SFTP protocols over native Unix sockets without requiring remote daemon installation.

#### 9. Embed & IoT Studio Mode (`.embedded`)
- **Purpose**: Hardware programming, micro-controller firmware deployment, and serial monitoring.
- **Why It Outperforms Competitors**:
  - Replaces clunky, disjointed CLI tooling with an integrated high-throughput serial terminal, real-time baud rate adjustment, and hardware flashing workflows for ESP32, STM32, Arduino, and Raspberry Pi.

#### 10. Science Mode (`.science`)
- **Purpose**: Deep computational workflows, bioinformatics pipeline orchestration, and genomic/chemical data analysis.
- **Why It Outperforms Competitors**:
  - Direct integration with computational biology databases and structure search tools without leaving the editor.

#### 11. Extension Studio Mode (`.extensions`)
- **Purpose**: Extension discovery, installation, and lifecycle management powered by Open VSX.
- **Why It Outperforms Competitors**:
  - Protects developer freedom by utilizing the open, vendor-neutral Open VSX marketplace rather than Microsoft's proprietary marketplace.
  - Emulates VS Code extension APIs via an isolated Node.js compatibility layer (`vscode-compat-host`) without running Electron.

#### 12. Native Ardium Toolchain Mode
- **Purpose**: Flagship development environment for the Ardium programming language (v2.3) developed by Dotmini Company Limited.
- **Why It Outperforms Competitors**:
  - Offers the world's only native IDE integration for Ardium, featuring Tree-sitter syntax highlighting, CoreUI declarative UI inspection, RAII `@owned` ownership analysis, and integrated compiler diagnostics.

---

## Core Engineering Specifications

MicroCode combines low-level macOS engineering with modern autonomous AI architectures:

### 1. Autonomous AI Agent and Implementation Planning Engine
MicroCode is a fully autonomous AI workstation with human-in-the-loop safety controls:
- **Formal Implementation Planning**: Before writing or altering code, the AI generates a structured, multi-phase plan detailing target files, architectural risks, and verification steps.
- **`⌘↵` Interactive Approval Gate**: High-risk tool calls (writing files, executing shell scripts, running git commands) pause at an interactive safety barrier requiring explicit developer approval.
- **Autonomous Multi-Agent Loop**: Capable of self-directed exploration, executing multi-turn tool cycles, diagnosing build errors, and self-correcting without intervention.
- **Sub-Agent Delegation**: Spawn specialized sub-agents running concurrently (e.g. `research` for codebase indexing, `flutter_a11y_agent` for accessibility audits, or isolated `self` workers).
- **Slash Commands**: Built-in developer shortcuts such as `/goal` (exhaustive execution), `/schedule` (timed background monitors), `/browser` (web scraping & docs), `/grill-me` (design interviews), and `/boost` (deep reasoning).
- **AST RepoMap & On-Device Memory**: Tree-sitter semantic symbol graphs and Candle ML vector embeddings give the agent continuous, deep context of your entire project topology.
- **Bi-Directional LSP Bridge**: The agent directly queries Language Server Protocols to inspect compiler diagnostics, type definitions, and real-time syntax errors.

### 2. SuperTab Predictive Autocomplete and Inline Diff Engine
A next-generation editing experience powered by speculative multi-token decoding:
- **SuperTab Speculative Predictions**: Analyzes real-time cursor trajectory, AST scope, and import graph to suggest complete multi-line statements and function blocks ahead of keystrokes.
- **Interactive Inline Diff Engine**: Visual chunk-based diff reviewer with syntax-aware highlight blending and one-click chunk accept/reject (`⌥↵`).
- **Smart Refactor & Unit Test Synthesis**: Context-menu code actions that transform legacy syntax, optimize algorithms, or synthesize exhaustive test suites directly in-place.

### 3. Embedded Device Dock and Hardware Simulation Hub
Test mobile and desktop applications without leaving your code editor:
- **iOS Simulator Live Stream**: Ultra-low latency H.264 video streaming over WebSockets directly into an editor tab via embedded `serve-sim` capture daemon.
- **Android Physical & Emulator Mirroring**: High-performance ADB screen mirroring via custom `scrcpy-server` streaming pipeline with full touch, scroll, and keyboard forwarding.
- **Photorealistic Metal 120 FPS Shaders**: Custom Metal shader pipeline rendering hardware device bezels, dynamic glass reflections, and simulated Dynamic Island / camera punch-holes at 120 Hz on ProMotion displays.

### 4. Open VSX Marketplace, Bidirectional ACP & 2-Way MCP Ecosystem
Extensibility and agent interoperability without Electron's memory bloat:
- **Bidirectional ACP (Agent Client Protocol)**: Act as an **ACP Host** to run external agents (Claude Code, Gemini CLI, Codex CLI, Goose) inside MicroCode's native UI and diff engine, or act as an **ACP Server** exposing MicroCode's agent over JSON-RPC 2.0 (`stdio` / WebSocket), plus real-time inline completions via **ACP Ghost Text Bridge**.
- **2-Way Model Context Protocol (MCP)**:
  - **MCP Client**: Connect to any external MCP server (databases, cloud APIs, browser tools, Slack/GitHub/Linear) with one-click import from Claude Desktop & Cursor configs.
  - **Built-In MicroCode IDE MCP Server**: Exposes **35+ native IDE capabilities** (`file_read`, `patch_file`, `find_symbol`, `lsp_intelligence`, `computer_use_*`, `device_interact`, `adb_execute`, `preview_control`, `cell_run`, `ardium_compile`, `api_studio`, `database_studio`) so external agents can control MicroCode directly.
- **Open VSX Marketplace Integration**: Search, download, install, and manage extensions directly from the open-source Open VSX registry.
- **VS Code Extension Compatibility Host**: Integrated Node.js runtime (`vscode-compat-host`) emulating VS Code extension APIs for syntax grammars, themes, and snippets.
- **Sandboxed WASM Plugins**: Embedded Wasmtime engine executing lightweight WebAssembly plugins with strict CPU/memory quotas and zero unauthorized disk access.

### 5. Native Developer Studios (Database, API, CI/CD, Notebooks)
Everything you need to build, test, and ship in one unified native workspace:
- **Database Studio**: Full SQL workbench supporting PostgreSQL, MySQL, and SQLite. Inspect schemas, browse table records, and execute queries with instant tabular results.
- **API Client Studio**: Native REST and GraphQL testing client with environment presets, auth token injectors, variable interpolation, and formatted JSON/XML payloads.
- **CI/CD Pipeline Viewer**: Direct GitHub Actions integration to track workflow runs, inspect step logs, and re-trigger jobs without context-switching to a browser.
- **Interactive Playground & Cell Notebooks**: REPL scratchpad supporting instant code execution across Swift, Rust, Python, and Ardium with rich visual outputs.

### 6. Real-Time CRDT Collaboration, AI Teammate & Voice Dictation
Designed for modern distributed engineering teams:
- **P2P & Tunnel Collaboration Engine**: Real-time multi-user document editing across Native macOS IDEs and the zero-install WebApp Collaboration Portal (`trycloudflare` / LAN / P2P) with live remote cursor presence and zero merge conflicts.
- **AI Agent Teammate (`MicroCode AI`) & Live Follow Mode**: Exclusively during active Collab sessions, `MicroCode AI` participates as a visible teammate with live cursor/line-range highlights in both the Native AppKit editor and WebApp editor, 1-click **Follow AI** auto-scrolling, and `@ai` command dispatch in Session Chat.
- **Voice Coding & Dictation**: Apple Speech-powered low-latency dictation and voice commands allowing hands-free code navigation and refactoring.

### 7. Enterprise Governance, Multi-Local LLM Pool & Multi-Workspace Concurrency
Built for both sovereign local workflows and enterprise security requirements:
- **Multi-Endpoint Local LLM Pool**: Connect simultaneously to multiple local and LAN inference servers (Ollama, LM Studio, vLLM, llama.cpp, Apple MLX, Dotmini Omni) with unified model routing and automatic node failover.
- **Concurrent Multi-Workspace Agents**: Run autonomous AI agents in parallel across multiple workspaces at the same time with isolated per-workspace state and tool sandboxes.
- **Enterprise DLP, Spend Caps & SHA-256 Audit Chain**: Pre-flight secret/PII redaction, Air-Gapped Local-Only enforcement, daily/monthly budget guardrails, and a tamper-evident SHA-256 hash-chained audit log.

### 8. Native Ardium Language Toolchain (v2.3)
Full first-class IDE support for the Ardium programming language:
- **Full Syntax & AST Grammar**: Native Tree-sitter parser with syntax highlighting, CoreUI declarative UI syntax, and RAII `@owned` ownership tracking.
- **Compiler Diagnostics & Runner**: In-editor diagnostic linting, playground evaluation, and live execution via `ArdiumRunner`.

### 9. Dotmini Cloud GPU Dispatch and Sovereign AI
High-performance compute offloading when local hardware isn't enough:
- **Cloud GPU Remote Dispatch**: One-click compute offloading to remote NVIDIA A100/H100 clusters for heavy training, fine-tuning, and batch inference.
- **Dotmini Omni Sovereign Models**: Native local support for Dotmini Omni O1X Lite (0.8B) and Omni O1X Pro (3B MoE) for privacy-preserving offline inference.

### 10. Native High-Performance macOS Core Architecture
- **Pure Swift + SwiftUI + AppKit**: Built specifically for macOS 13+ (Ventura, Sonoma, Sequoia). Zero web engine overhead.
- **Metal GPU Text Pipeline**: Smooth 120 FPS kinetic scrolling, sub-second cold boot, and less than 80 MB idle RAM consumption.
- **Full PTY Terminal**: Native virtual terminal with ANSI 24-bit TrueColor, zsh/bash integration, and split panes.

---

## Architecture

```mermaid
flowchart TB
    %% ==========================================
    %% MicroCode High-Performance Architecture
    %% ==========================================

    subgraph Client [" 🖥️ Native macOS Client Layer (Swift 5.9 • AppKit • Metal 120 FPS) "]
        direction LR
        subgraph UI [" 🎨 Presentation & Studios "]
            Editor["<b>Native Code Editor</b><br/>AppKit NSTextView • Kinetic"]
            Planning["<b>AI Agent Workboard</b><br/>Interactive Plan & Tool Approval"]
            Studios["<b>Developer Studios</b><br/>DB • API • Cell Mode • REPL"]
        end

        subgraph MetalEngine [" ⚡ Metal GPU Pipeline "]
            MetalShader["<b>Metal Render Engine</b><br/>Direct GPU Text Rasterization"]
            DeviceDock["<b>Live Device Dock</b><br/>Interactive H.264 & ADB Bezels"]
            LiquidGlass["<b>Liquid Glass UI</b><br/>Native macOS Vibrant Materials"]
        end

        subgraph ObjCCore [" 🧩 Objective-C++ Engine "]
            TextBuffer["<b>High-Speed Gap Buffer</b><br/>Zero-Cost Buffer Mutations"]
            TokenLayout["<b>Token Layout Primitives</b><br/>Native C Memory Structures"]
        end
    end

    Bridge(["⚡ <b>MicroCode Kernel Bridge</b> — Low-Latency C ABI • Unix Domain Sockets • Zero-Copy Pipes"])

    subgraph RustCore [" 🦀 Embedded Core Engine (Rust Tokio • Axum Microservice) "]
        direction TB
        subgraph AIService [" 🧠 Autonomous AI & Protocol Engine "]
            AgentEngine["<b>Autonomous Agent Loop</b><br/>Multi-Turn Self-Healing Engine"]
            ModelCatalog["<b>Dynamic Model Discovery</b><br/>Real-Time Provider Discovery"]
            MCPCore["<b>MCP Protocol Manager</b><br/>Anthropic Model Context Protocol"]
        end

        subgraph CodeIntel [" 🔍 Semantic Intelligence & Indexing "]
            TreeSitter["<b>Tree-sitter AST Engine</b><br/>Incremental Parsing • 30+ Languages"]
            CandleVector["<b>Candle ML Vector Store</b><br/>On-Device Semantic RAG Indexing"]
            CRDTCore["<b>CRDT Realtime Sync</b><br/>Decentralized P2P Collaborative Editing"]
        end

        subgraph SystemSec [" 🛡️ Systems, Sandbox & Toolchains "]
            SandboxCore["<b>Workspace Sandbox Boundary</b><br/>Path Traversal & Safe Command Gate"]
            PTYTerminal["<b>PTY Terminal Harness</b><br/>24-Bit ANSI TrueColor Virtual Terminal"]
            WasmHost["<b>Wasmtime & VSX Host</b><br/>Sandboxed Extensions & Runtime Isolation"]
        end
    end

    subgraph External [" 🌐 Multi-Provider AI & External Compute Ecosystem "]
        direction LR
        subgraph CloudAI [" ☁️ Real-Time Cloud AI (BYOK) "]
            CloudModels["<b>Tier-1 AI Providers</b><br/>Gemini • OpenAI • Claude • Grok • DeepSeek"]
        end

        subgraph LocalAI [" 🏠 Local Sovereign AI "]
            LocalModels["<b>On-Device LLM Runtimes</b><br/>Apple MLX • Ollama (11434) • Dotmini Omni"]
        end

        subgraph Hardware [" 📱 Live Hardware Streams "]
            Devices["<b>Embedded Mobile Simulators</b><br/>Android ADB scrcpy • iOS Simulator"]
        end

        subgraph HeavyCompute [" 🚀 High-Compute & Language "]
            CloudGPU["<b>Dotmini Cloud GPU</b><br/>NVIDIA A100 / H100 Remote Cluster Dispatch"]
            ArdiumLang["<b>Ardium v2.3 Native</b><br/>Compiler, AST & CoreUI Engine"]
        end
    end

    %% Wiring
    UI --> Bridge
    MetalEngine --> Bridge
    ObjCCore --> Bridge

    Bridge <===> RustCore

    AIService <===> CloudAI
    AIService <===> LocalAI
    SystemSec <===> Hardware
    RustCore <===> HeavyCompute

    %% Styles & Colors
    classDef clientCard fill:#0f172a,stroke:#38bdf8,stroke-width:1.5px,color:#f8fafc;
    classDef metalCard fill:#18181b,stroke:#f43f5e,stroke-width:1.5px,color:#f8fafc;
    classDef objcCard fill:#1c1917,stroke:#fb923c,stroke-width:1.5px,color:#f8fafc;
    classDef bridgeNode fill:#312e81,stroke:#a855f7,stroke-width:2px,color:#ffffff;
    classDef aiCard fill:#022c22,stroke:#10b981,stroke-width:1.5px,color:#f8fafc;
    classDef intelCard fill:#1e1b4b,stroke:#818cf8,stroke-width:1.5px,color:#f8fafc;
    classDef secCard fill:#2e1065,stroke:#c084fc,stroke-width:1.5px,color:#f8fafc;
    classDef extCloud fill:#082f49,stroke:#0ea5e9,stroke-width:1.5px,color:#f8fafc;
    classDef extLocal fill:#064e3b,stroke:#34d399,stroke-width:1.5px,color:#f8fafc;
    classDef extDev fill:#451a03,stroke:#f59e0b,stroke-width:1.5px,color:#f8fafc;
    classDef extComp fill:#3b0764,stroke:#e879f9,stroke-width:1.5px,color:#f8fafc;

    class Editor,Planning,Studios clientCard;
    class MetalShader,DeviceDock,LiquidGlass metalCard;
    class TextBuffer,TokenLayout objcCard;
    class Bridge bridgeNode;
    class AgentEngine,ModelCatalog,MCPCore aiCard;
    class TreeSitter,CandleVector,CRDTCore intelCard;
    class SandboxCore,PTYTerminal,WasmHost secCard;
    class CloudModels extCloud;
    class LocalModels extLocal;
    class Devices extDev;
    class CloudGPU,ArdiumLang extComp;
```

### Tech Stack

| Subsystem | Technology | Responsibility |
|:----------|:-----------|:---------------|
| **UI & Windowing** | SwiftUI + AppKit | Declarative macOS UI, native windowing, trackpad gestures |
| **GPU Rendering** | Metal Shaders | 120 FPS device frame shaders, GPU-accelerated text & animations |
| **Core Text Buffer** | Objective-C++ & C ABI | Memory-efficient text gap buffer and high-performance primitives |
| **Backend Core** | Rust (Axum + Tokio) | Async microservices, multi-provider AI streaming, Git, process harness |
| **Syntax & AST** | Tree-sitter | Real-time AST parsing for 30+ languages, symbol indexing & RepoMap |
| **Semantic Intelligence** | Candle ML | On-device vector embeddings and local RAG code search |
| **Extension Runtime** | Open VSX + Node.js + Wasmtime | Marketplace registry, VS Code API compatibility, and WASM sandboxing |
| **AI Tool Protocol** | Model Context Protocol (MCP) | Client & server support for Anthropic MCP tools & resources |
| **Device Simulation** | ADB / scrcpy + serve-sim | Hardware-accelerated screen mirroring for Android & iOS Simulator |
| **Realtime Sync** | CRDT Engine | Decentralized, conflict-free collaborative editing and presence |
| **Native Toolchains** | Swift, Rust, Ardium v2.3 | Multi-language compilation, diagnostics, and interactive playground |

---

## Getting Started

### Requirements

| Requirement | Version |
|------------|---------|
| macOS | 13.0 (Ventura) or later |
| Xcode | 15.0+ |
| Rust | 1.75+ |
| Node.js | 18+ (optional, for extension development) |

### Install from Release

Download directly from our official portal at [**microcode.dotmini.net**](https://microcode.dotmini.net) or from [**GitHub Releases (v2.5.40)**](https://github.com/Dotmini/microcode/releases/tag/v2.5.40):

| Package | Architecture | Direct Download Link |
|:---|:---:|:---|
| 💿 **macOS Disk Image (DMG)** | Apple Silicon (ARM64) / Intel (x86_64) | [**Download MicroCode v2.5.40 DMG**](https://github.com/Dotmini/microcode/releases/tag/v2.5.40) |
| 📦 **Component Installer (PKG)** | Apple Silicon (ARM64) / Intel (x86_64) | [**Download MicroCode v2.5.40 PKG**](https://github.com/Dotmini/microcode/releases/tag/v2.5.40) |
| 📄 **Cryptographic Checksums** | All (`SHA256SUMS.txt`) | [**View v2.5.40 Release Checksums**](https://github.com/Dotmini/microcode/releases/tag/v2.5.40) |

> **System Requirements**: macOS 13.0 (Ventura) or later · Native on Apple Silicon (M1/M2/M3/M4/M5).  
> **Official Portal & Updates**: [https://microcode.dotmini.net](https://microcode.dotmini.net)

### Build from Source

For detailed instructions and prerequisites, see [**BUILDING.md**](BUILDING.md).

```bash
# Clone the repository
git clone https://github.com/Dotmini/microcode.git
cd microcode

# 1. Standard full build (Rust backend + Swift frontend -> MicroCode.app)
./build.sh

# 2. Fast development build with auto-deployment to ~/Applications
./build_dev.sh

# 3. Distribution release (universal binary + DMG + PKG)
./build_distribution.sh
```

### Common Build Flags (`build.sh`)

```bash
./build.sh --debug          # Build with debug symbols
./build.sh --frontend-only  # Recompile Swift app only (uses existing Rust libs)
./build.sh --backend-only   # Recompile Rust backend and FFI only
./build.sh --clean          # Clean build artifacts before compiling
./build.sh --external-ssd   # Offload caches & artifacts to external SSD
```

---

## Project Structure

```
microcode/
├── MicroCode/               # Swift sources (SwiftUI + AppKit)
│   ├── Views/               # UI components (Editor, AI Workboard, Studios, Device Dock, Git)
│   ├── Services/            # AI agent loop, SuperTab, CRDT, LSP bridge, Device streaming
│   ├── SyntaxEngine/        # Syntax highlighting and theme engine
│   └── Models/              # AppState, ImplementationPlan, tool approval gates, config
├── MicroCodeSupport/        # Objective-C++ core and text buffer bridge
├── MicroCodeKernel/         # Native AppKit/Metal text kernel
├── MicrocodeCoreSupport/    # Rust FFI headers and C ABI bridge
├── backend/                 # Rust backend server (Axum + Tokio)
│   └── src/
│       ├── ai.rs            # Multi-provider AI engine (Gemini, Claude, GPT, DeepSeek, etc.)
│       ├── agent.rs         # Autonomous AI agent loop with tool approval gate
│       ├── indexer.rs       # Tree-sitter file indexer & symbol search
│       └── main.rs          # Axum HTTP API & WebSocket server
├── microcode_core/          # Rust shared core library (libmicrocode_core.a)
├── extension-host/          # Sandboxed WASM extension runtime
├── vscode-compat-host/      # VS Code extension compatibility layer
├── Vendor/                  # Pre-compiled simulator & device capture utilities (serve-sim, scrcpy)
├── tools/                   # Developer utilities, migration & scratch tests
└── .github/workflows/       # CI/CD (build, sign, release)
```

---

## Security & Code Integrity

MicroCode is engineered with enterprise-grade defense-in-depth:

- **100-Step Deep Security & Secret Leak Audit**: All tracked source code, commit history, and release packages pass our exhaustive 100-step credential scan. Zero hardcoded API keys, JWTs, or private keys.
- **Strict Sandbox Isolation**: AI agent file edits and terminal commands are constrained to the active workspace directory with strict path boundary validation.
- **Human-in-the-Loop (`⌘↵`) Gate**: High-risk tool calls (writing files, executing shell scripts, running git commands) are paused until explicitly authorized by the developer.
- **Cryptographic Source Integrity**: 442 source files verified with SHA256 checksums (`CHECKSUMS.sha256`) checked in CI.
- **macOS Keychain Storage**: User API keys and sessions are stored in the secure macOS Keychain (Apple Security Framework), never in plain-text project files.

---

## AI Provider Setup: Subscriptions, ACP, MCP, BYOK & Local LLM Pool

MicroCode supports **four unified ways to power AI** inside the IDE — switchable on the fly from the chat bar:

### 1. Direct Subscription Login (Zero Per-Token API Fees)
Sign in with your existing AI subscription via 1-Click OAuth or embedded web session (`SubscriptionAuthManager` & `LocalSubscriptionGatewayService`):

| Subscription Provider | Supported Plans | Auth Method | Capabilities in MicroCode |
|:---|:---|:---|:---|
| **OpenAI ChatGPT** | Plus / Pro / Team | OAuth / Session Bridge | Autonomous Agent, Codex, ACP Ghost Text |
| **Anthropic Claude** | Pro / Max / Team | OAuth / Claude Code CLI | Autonomous Agent, Extended Thinking, ACP |
| **Google Gemini** | Gemini Advanced / CodeAssist | Google OAuth 2.0 | Autonomous Agent, 1M+ Context, Multimodal |
| **GitHub Copilot** | Individual / Business / Enterprise | GitHub Device OAuth | SuperTab Autocomplete, Chat & Agent |
| **Qwen / Kimi / GLM** | Consumer & Pro Subscriptions | Web Session / OAuth | Multi-turn Coding Agent & Fast Completions |

### 2. Agent Client Protocol (ACP) & Model Context Protocol (MCP)

| Protocol | Direction | Implementation | What It Enables |
|:---|:---|:---|:---|
| **ACP Host** | External Agent → MicroCode UI | `ACPHostService` (JSON-RPC 2.0 `stdio`) | Run `claude`, `gemini`, `codex`, `goose`, or custom ACP agents inside MicroCode with native diff cards & `⌘↵` approval |
| **ACP Server** | External Client → MicroCode Agent | `ACPServerService` (`stdio` / WS) | Drive MicroCode's autonomous agent and workspace tools from external orchestrators |
| **ACP Ghost Text** | ACP Agent → Editor Inline | `ACPGhostTextBridge` | Low-latency inline ghost-text completions powered by your active ACP agent |
| **MCP Client** | External MCP → MicroCode Agent | `ExternalMCPManager` (`stdio` / SSE) | Auto-discover & call tools from Claude Desktop / Cursor MCP servers inside MicroCode |
| **MCP Server** | External Agent → MicroCode IDE | `MCPServer` / `microcode_mcp` (`35+ tools`) | Let any MCP client control MicroCode's Editor, LSP, Device Dock, ADB/simctl, Computer Use, DB & API Studios |

### 3. Supported Cloud & Local Providers (BYOK + Multi-Endpoint Local Pool)

MicroCode also features a **100% Real-Time Model Discovery Engine** (`/v1/models`) with zero hardcoding:

| Provider | Model Discovery | Local / Cloud | Environment Variable | Configuration View |
|:---|:---|:---:|:---|:---|
| **Google Gemini** | Real-time via Gemini API v1beta | Cloud | `GEMINI_API_KEY` | Settings → AI Providers → Gemini |
| **OpenAI** | Real-time via `/v1/models` | Cloud | `OPENAI_API_KEY` | Settings → AI Providers → OpenAI |
| **Anthropic Claude** | Real-time live endpoint | Cloud | `ANTHROPIC_API_KEY` | Settings → AI Providers → Anthropic |
| **DeepSeek** | Real-time via OpenAI-compat API | Cloud | `DEEPSEEK_API_KEY` | Settings → AI Providers → DeepSeek |
| **xAI Grok** | Real-time via `/v1/models` | Cloud | `GROK_API_KEY` | Settings → AI Providers → Grok |
| **Multi-Node Local LLM Pool** | Concurrent discovery across Ollama (`11434`), LM Studio (`1234`), vLLM (`8000`), llama.cpp (`8080`), Apple MLX & LAN/Tailscale nodes | **Local / LAN Pool** | None (Multi-endpoint pool) | Settings → AI Providers → Local LLM |
| **Alibaba Qwen** | Real-time DashScope endpoint | Cloud | `QWEN_API_KEY` | Settings → AI Providers → Qwen |
| **Zhipu GLM** | Real-time BigModel endpoint | Cloud | `GLM_API_KEY` | Settings → AI Providers → GLM |
| **Dotmini Omni** | Sovereign AI (0.8B / 3B MoE) | **Local / Cloud** | `DOTMINI_PLATFORM_KEY` | Settings → AI Providers → Dotmini |

> [!TIP]
> **Zero Middleman Markup**: Your API requests travel directly between your Mac and the AI provider endpoint via low-latency streaming SSE (Server-Sent Events). MicroCode never proxies, stores, or marks up your token usage.

---

## Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Run checksums before committing (`./generate_checksums.sh`)
4. Submit a pull request

---

## Credits

<table>
  <tr>
    <td align="center">
      <strong>Tirawat Nantamas (ถิรวัฒน์ นันตมาศ)</strong><br/>
      <em>Founder & CEO</em><br/>
      <a href="https://dotmini.net">Dotmini Company Limited (บริษัท ดอทมินิ จำกัด)</a><br/>
      🌐 <a href="https://microcode.dotmini.net"><strong>microcode.dotmini.net</strong></a>
    </td>
  </tr>
</table>

---

## Intellectual Property & License (ทรัพย์สินทางปัญญาและข้อกำหนดการใช้งาน)

> ### ข้อกำหนดทางกฎหมายและสิทธิ์ในทรัพย์สินทางปัญญา (Legal Notice)
> ซอฟต์แวร์ ซอร์สโค้ด สถาปัตยกรรม และองค์ประกอบทั้งหมดของ **MicroCode** เป็น **ทรัพย์สินทางปัญญาของ บริษัท ดอทมินิ จำกัด (Dotmini Company Limited) แต่เพียงผู้เดียวเท่านั้น**

โปรเจกต์นี้เปิดให้เข้าถึงซอร์สโค้ด (Source-Available) ภายใต้สัญญาอนุญาต **Elastic License v2 (ELv2)** และเงื่อนไข Business Source License (BSL) โดยมีข้อกำหนดห้ามอย่างเด็ดขาดดังต่อไปนี้:

1. **ห้ามนำไปพัฒนาต่อเพื่อการค้า (No Commercial Fork / Continuation)**: ไม่อนุญาตให้นำซอร์สโค้ดไปพัฒนาต่อยอด ดัดแปลงเพื่อแยกทำเวอร์ชันใหม่ หรือทำเป็นโปรดักต์เชิงพาณิชย์โดยไม่ได้รับอนุญาตเป็นลายลักษณ์อักษรจาก บริษัท ดอทมินิ จำกัด
2. **ห้ามนำไปขาย หรือนำไปทำ Product เด็ดขาด (No Commercial Sale / Packaging)**: ห้ามนำซอร์สโค้ด, ไบนารี, ส่วนประกอบ หรืออนุพันธ์ของซอฟต์แวร์นี้ไปจำหน่าย จำหน่ายต่อ ทำแพ็กเกจขาย หรือนำไปให้บริการเชิงพาณิชย์ (เช่น Cloud/Managed Service หรือ SaaS) โดยเด็ดขาด
3. **ห้ามนำไป ReBrand ขายทุกกรณี (Strictly Prohibited from Rebranding / White-labeling)**: ห้ามทำการเปลี่ยนชื่อ เปลี่ยนตราสัญลักษณ์ ลบเครดิต ปลอมแปลง หรือทำ White-label เพื่อนำไปแจกจ่ายหรือแสวงหาผลประโยชน์ทางการค้าในทุกกรณี

### การใช้งานที่อนุญาต (Permitted Use)
- **การศึกษา ค้นคว้า และเรียนรู้ส่วนบุคคล (Personal Learning & Educational Use)**: สามารถดาวน์โหลดและศึกษาโค้ดเพื่อการวิจัย เรียนรู้ และตรวจสอบความโปร่งใสของระบบได้
- **การประเมินผลภายใน (Internal Evaluation)**: สามารถทดลองรันเพื่อทดสอบการทำงานภายในองค์กรแบบ Non-production ได้

---

### Jurisdiction & Governing Law (เขตอำนาจศาลและกฎหมายที่ใช้บังคับ)

ข้อกำหนดและสัญญาอนุญาตนี้อยู่ภายใต้บังคับแห่ง **กฎหมายไทย (Thai Law)**:
- พระราชบัญญัติลิขสิทธิ์ พ.ศ. 2537 และที่แก้ไขเพิ่มเติม
- ประมวลกฎหมายแพ่งและพาณิชย์
- พระราชบัญญัติความลับทางการค้า พ.ศ. 2545

ข้อพิพาทใดๆ ให้ระงับโดยศาลทรัพย์สินทางปัญญาและการค้าระหว่างประเทศกลาง ณ **กรุงเทพมหานคร ประเทศไทย**

---

<p align="center">
  <sub>Developed by <a href="https://dotmini.net">Dotmini Company Limited</a> · Official Portal: <a href="https://microcode.dotmini.net">microcode.dotmini.net</a></sub><br/>
  <sub>Copyright © 2024-2026 Tirawat Nantamas — Dotmini Company Limited (บริษัท ดอทมินิ จำกัด). All rights reserved.</sub>
</p>

