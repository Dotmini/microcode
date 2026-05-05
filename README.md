<p align="center">
  <img src="MicroCOdeDoogleIcon.png" alt="MicroCode" width="420" />
</p>

<h1 align="center">MicroCode</h1>

<p align="center">
  <strong>The Native AI-Powered IDE for macOS</strong><br/>
  <em>Built from scratch. No Electron. No compromises.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS_13+-black?style=flat-square&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/Rust-1.75+-DEA584?style=flat-square&logo=rust&logoColor=white" />
  <img src="https://img.shields.io/badge/Metal-GPU_Accelerated-8E8E93?style=flat-square&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/License-MPL_v1.0-blue?style=flat-square" />
  <img src="https://img.shields.io/github/v/release/Dotmini/microcode?style=flat-square&color=green" />
</p>

<p align="center">
  <a href="https://github.com/Dotmini/microcode/releases/latest"><strong>⬇️ Download Latest Release</strong></a> ·
  <a href="#features"><strong>Features</strong></a> ·
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
| **AI integration** | 7 providers, native | Plugin-dependent |
| **File indexing** | Tree-sitter + Rust | JS-based |

---

## Features

### 🧠 AI Agent — Production Grade
Multi-provider AI agent with tool-use capabilities, not just autocomplete.

- **7 providers** — Gemini, OpenAI, Claude, DeepSeek, Grok, Qwen, GLM
- **Agentic tools** — Read, write, edit, search code, run commands, git operations
- **Streaming responses** — Real-time token streaming with diff preview
- **Workspace-aware** — Full project context via RAG semantic search (Candle ML)
- **Sandboxed execution** — Timeout, output limits, path-restricted operations

### ⚡ Editor — Zero-Latency
- **30+ languages** — Tree-sitter powered syntax highlighting
- **Debounced highlighting** — Only processes visible range, not the entire file
- **Hex color preview** — Inline color swatches in CSS/Swift/Rust
- **Native text engine** — NSTextView + custom layout, not a web canvas

### 🖥️ Integrated Terminal
- Full PTY terminal with ANSI color support
- Multiple sessions with tab management
- Direct workspace integration

### 🔧 Developer Workflow
- **Git integration** — Status, diff, commit, branch switching
- **Project scaffolding** — Create Rust, Swift, Node.js, Python, Web projects
- **WASM extensions** — Sandboxed extension system (Wasmtime)
- **Build system** — Integrated build & run for multiple languages

### 🎨 Design Language
- **Dark-first UI** — Precision-crafted dark theme with glassmorphism
- **Metal-powered effects** — GPU-rendered backgrounds and animations
- **Native macOS** — Respects system appearance, keyboard shortcuts, trackpad gestures

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MicroCode.app                             │
│                                                             │
│  ┌──────────────────┐  ┌──────────────────────────────────┐ │
│  │   SwiftUI + AppKit │  │   Objective-C++ Core              │ │
│  │                    │  │   • Syntax Engine                 │ │
│  │   • Editor View    │  │   • Text Pipeline                 │ │
│  │   • AI Agent Panel │  │   • Performance Primitives        │ │
│  │   • File Browser   │  │                                   │ │
│  │   • Terminal       │  └──────────────────────────────────┘ │
│  │   • Settings       │                                      │
│  └────────┬───────────┘                                      │
│           │ HTTP + SSE                                        │
│  ┌────────▼───────────────────────────────────────────────┐  │
│  │              Rust Backend (Axum + Tokio)                │  │
│  │                                                         │  │
│  │   ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐ │  │
│  │   │ AI      │ │ Agent    │ │ Git      │ │ Extension │ │  │
│  │   │ Engine  │ │ Runtime  │ │ Manager  │ │ Host      │ │  │
│  │   └─────────┘ └──────────┘ └──────────┘ └───────────┘ │  │
│  │   ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐ │  │
│  │   │ RAG     │ │ Terminal │ │ Indexer  │ │ Kernel    │ │  │
│  │   │ Search  │ │ Manager  │ │ (T-S)   │ │ Safety    │ │  │
│  │   └─────────┘ └──────────┘ └──────────┘ └───────────┘ │  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Frontend** | SwiftUI + AppKit | Native macOS UI |
| **Rendering** | Metal | GPU-accelerated effects |
| **Core** | Objective-C++ | Performance-critical text ops |
| **Backend** | Rust (Axum/Tokio) | Async services, AI, Git |
| **Parsing** | Tree-sitter | Multi-language syntax |
| **ML** | Candle | On-device embeddings for RAG |
| **Extensions** | Wasmtime | Sandboxed WASM plugins |

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

Download the latest `.dmg` or `.pkg` from [**Releases**](https://github.com/Dotmini/microcode/releases/latest).

### Build from Source

```bash
# Clone
git clone https://github.com/Dotmini/microcode.git
cd microcode

# Quick dev build (current arch, debug)
./build_distribution.sh --dev

# Full release build (universal binary + DMG + PKG)
./build_distribution.sh
```

### Build Options

```bash
./build_distribution.sh --dev          # Fast debug build, current arch only
./build_distribution.sh --version 1.1  # Set version
./build_distribution.sh --sign         # Sign & notarize after build
```

---

## Project Structure

```
microcode/
├── CodeTunner/              # Swift sources (SwiftUI + AppKit)
│   ├── Views/               # UI components
│   ├── Services/            # AI client, agent service
│   ├── SyntaxEngine/        # Highlighting engine
│   └── Models/              # Data models, app state
├── CodeTunnerSupport/       # Objective-C++ core modules
├── backend/                 # Rust backend server
│   └── src/
│       ├── ai.rs            # Multi-provider AI engine
│       ├── agent.rs         # AI agent with tool-use
│       ├── indexer.rs       # Tree-sitter file indexer
│       └── main.rs          # Axum HTTP server
├── microcode_core/          # Rust shared core library
├── extension-host/          # WASM extension runtime
├── vscode-compat-host/      # VS Code extension compatibility
└── .github/workflows/       # CI/CD (build, sign, release)
```

> **Note**: The `CodeTunner` folder name is historical. The product name is **MicroCode**.

---

## Security

MicroCode takes security seriously:

- **Source integrity** — SHA256 checksums verified on every push via CI
- **Sandboxed commands** — AI agent commands run with 30s timeout, 1MB output limit, restricted PATH
- **Path traversal protection** — All file operations validated against workspace boundary
- **No telemetry** — Zero data collection, fully offline capable

---

## AI Provider Setup

MicroCode supports 7 AI providers out of the box. Configure via **Settings → AI Providers**:

| Provider | Models | API Key Env |
|----------|--------|-------------|
| **Gemini** | 3.1 Pro, 2.5 Pro, 2.5 Flash | `GEMINI_API_KEY` |
| **OpenAI** | GPT-5, GPT-4o, o3, o4-mini | `OPENAI_API_KEY` |
| **Claude** | 4.7 Opus, Sonnet 4, 3.5 Haiku | `ANTHROPIC_API_KEY` |
| **DeepSeek** | V4, Chat, Coder | `DEEPSEEK_API_KEY` |
| **Grok** | grok-3, grok-3-mini | `GROK_API_KEY` |
| **Qwen** | qwen-max, qwen-turbo | `QWEN_API_KEY` |
| **GLM** | glm-4-plus | `GLM_API_KEY` |

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
    <td align="center"><strong>Tirawat Nantamas</strong><br/><em>Founder & Lead Architect</em><br/>Dotmini Software</td>
  </tr>
</table>

**Academic Partnership**: SPU AI Club — Sripatum University (มหาวิทยาลัยศรีปทุม)

---

## License

**MicroCode Public License (MPL) v1.0** — See [`LICENSE`](LICENSE) for full terms.

This is a **source-available** license designed to protect the creator's rights while fostering open-source collaboration:

| Use Case | Allowed? | Cost |
|----------|----------|------|
| 🏠 **Personal / Hobby** | ✅ Free | $0 |
| 🎓 **Education / Research** | ✅ Free | $0 |
| 🤝 **Open Source Contributions** | ✅ Free | $0 |
| 🔍 **Evaluation** (≤ 90 days) | ✅ Free | $0 |
| 🏢 **Commercial** (Small Biz ≤ ฿10M) | ⚠️ Requires CLA | **10% Revenue Share** |
| 🏬 **Commercial** (Medium ≤ ฿100M) | ⚠️ Requires CLA | **15% Revenue Share** |
| 🏛️ **Commercial** (Enterprise > ฿100M) | ⚠️ Requires CLA | **20% Revenue Share** |

### Commercial License Agreement (CLA)

If you intend to use MicroCode or any derivative work for **commercial purposes** (SaaS, product integration, consulting, etc.), you **must** sign a Commercial License Agreement with the Licensor before deployment:

1. **Contact** → [Dotmini Software](https://github.com/Dotmini) via GitHub
2. **Negotiate** → Revenue tier + specific terms
3. **Sign CLA** → Bilateral agreement with quarterly reporting
4. **Deploy** → Use commercially with full legal protection

> **⚠️ Using MicroCode commercially without a CLA is a violation of copyright law** under the Copyright Act B.E. 2537 (Thailand) and applicable international treaties.

### Jurisdiction

This license is governed by **Thai law** (กฎหมายไทย), including:
- Copyright Act B.E. 2537 (พ.ร.บ. ลิขสิทธิ์)
- Civil and Commercial Code (ประมวลกฎหมายแพ่งและพาณิชย์)
- Trade Secrets Act B.E. 2545 (พ.ร.บ. ความลับทางการค้า)

Disputes are resolved in the courts of **Bangkok, Thailand**.

---

## Credits

<table>
  <tr>
    <td align="center"><strong>Tirawat Nantamas (ธีรวัฒน์ นันทมาศ)</strong><br/><em>Founder & Lead Architect</em><br/>Dotmini Software</td>
  </tr>
</table>

**Academic Partnership**: SPU AI Club — Sripatum University (มหาวิทยาลัยศรีปทุม)

---

<p align="center">
  <sub>Built with ❤️ in Thailand 🇹🇭</sub><br/>
  <sub>Copyright © 2024-2026 Tirawat Nantamas — Dotmini Software</sub>
</p>
