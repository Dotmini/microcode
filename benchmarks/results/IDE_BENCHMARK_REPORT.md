# MicroCode Official Production IDE Benchmark Report (v2.5.32)

> **100% Controlled-Variable Empirical Benchmark across macOS Desktop IDEs**  
> **Date (UTC):** `2026-10-26T08:58:24Z`  
> **Benchmark Harness:** [`benchmarks/run_ide_benchmarks.py`](file:///Users/dotmini/Documents/SX/codetunner-native/benchmarks/run_ide_benchmarks.py) & [`benchmarks/window_probe.swift`](file:///Users/dotmini/Documents/SX/codetunner-native/benchmarks/window_probe.swift)  
> **Raw Telemetry JSON:** [`benchmarks/results/ide_benchmark_results.json`](file:///Users/dotmini/Documents/SX/codetunner-native/benchmarks/results/ide_benchmark_results.json)

---

## 1. Controlled Variables (ตัวแปรควบคุมเดียวกัน 100%)

Every IDE in this benchmark was evaluated on the exact same physical machine, during the same test session, opening the exact same deterministic workspace fixture from a clean process state:

| Controlled Variable | Specification |
| :--- | :--- |
| **SoC / Processor** | Apple M2 (`8 Cores`: 4 Performance + 4 Efficiency, `arm64`) |
| **Unified Memory** | `16 GB` LPDDR5 (`17,179,869,184` bytes) |
| **Operating System** | macOS `27.0` (Build `26A5388g`, Darwin `arm64`) |
| **Controlled Workspace Corpus** | `500` polyglot source files (`200` Swift, `150` TypeScript/React, `100` Rust, `50` Python = **`49,350` LOC**) |
| **Primary Entry File Opened** | `src/core/BenchmarkCoreEngine.swift` (**`4,996` lines**) |
| **Large File Stress Corpus** | `data/LargeDatasetMatrix.json` (**`100,000` lines**, `12.28 MB` total fixture) |
| **Workspace SHA-256 Manifest** | `c5504e49e51fe7af09eac5398dd6573488bb7dc7c1db2d485c0428af1d946f2f` |
| **Process Isolation & Trials** | Full process-tree termination prior to each launch; `1` warmup + **`5` measured trials** per IDE |
| **Cold-Start Instrumentation** | Native CoreGraphics `CGWindowListCopyWindowInfo` polled at **`500 Hz` (`2 ms` interval)** until `kCGWindowLayer == 0` on-screen window ready |
| **Memory Instrumentation** | Full process-tree Resident Set Size (`RSS`) summed across Main + GPU + Renderer + Extension Host + Sidecar child processes at steady state |

---

## 2. Executive Summary (Median of $N = 5$ Controlled Trials)

| IDE & Version | Core Architecture & UI Engine | Cold Start (Median) | Cold Start (Min) | Memory RSS (Median) | OS Processes | Mach Threads | App Bundle Size |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **MicroCode IDE `v2.5.32`** | **Native Swift + Metal 3 + Rust Core** (`AppKit / SwiftUI`) | **`493.0 ms`** | **`458.7 ms`** | **`194.8 MB`** | **`1`** | **`20`** | **`95.7 MB`** |
| **OpenCode Desktop `v1.2.4`** | Tauri + WebKit + Rust/Node Sidecar (`WKWebView`) | `566.7 ms` | `544.9 ms` | `214.6 MB` | `2` | `37` | `156.3 MB` |
| **Zed `v1.18.0`** | Native Rust + GPUI (`Metal Shaders`) | `798.4 ms` | `695.1 ms` | `219.2 MB` | `2` | `47` | `401.6 MB` |
| **VS Code / Code-OSS `v2.5.5`** | Electron + Chromium + V8 + Node.js (`Blink DOM`) | `2,186.1 ms` | `1,854.8 ms` | `941.7 MB` | `6`–`16` | `112`–`151` | `733.4 MB` |
| *Electron AI IDE (Active Multi-Window Ref)* | *Electron + Multi-Renderer + Node Agent Host* | *—* | *—* | *`3,029.8 MB`* | *`37`* | *`451`* | *`471.3 MB`* |

### Key Empirical Findings
- **Cold-Start Speed**: **MicroCode IDE (`493.0 ms` median / `458.7 ms` min)** is **`4.43x` faster** than Electron / VS Code (`2,186.1 ms`), **`1.62x` faster** than Zed (`798.4 ms`), and has **`6.2x` lower launch jitter** ($\sigma = 45.0\text{ ms}$) than WebKit/Tauri (`\sigma = 279.1\text{ ms}`).
- **Memory Efficiency**: **MicroCode IDE (`194.8 MB` median / `173.5 MB` min)** runs inside **a single native macOS process (`1` process, `20` threads)** — consuming **`4.83x` less RAM** than a clean single-window Electron IDE (`941.7 MB`) and **`15.5x` less RAM** than an active multi-window Electron AI IDE session (`3,029.8 MB` across `37` processes).
- **Disk Footprint**: At **`95.7 MB`**, MicroCode's native bundle is **`7.66x` smaller** than Electron (`733.4 MB`) and **`4.20x` smaller** than Zed (`401.6 MB`) because it links directly against macOS system frameworks (`AppKit`, `Metal`, `CoreText`) rather than bundling a private copy of Chromium and Node.js.

---

## 3. Raw Trial-by-Trial Data ($N = 5$ Controlled Runs per IDE)

### 3.1 Cold-Start Latency to On-Screen Window (`ms`, Lower is Better)

| IDE | Trial 1 | Trial 2 | Trial 3 | Trial 4 | Trial 5 | Median | Mean | StdDev ($\sigma$) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **MicroCode IDE `v2.5.32`** | `493.0` | `576.1` | `505.5` | `458.7` | `476.7` | **`493.0 ms`** | **`502.0 ms`** | `45.00 ms` |
| **OpenCode Desktop `v1.2.4`** | `562.6` | `1053.1` | `566.7` | `1081.2` | `544.9` | `566.7 ms` | `761.7 ms` | `279.13 ms` |
| **Zed `v1.18.0`** | `771.7` | `798.4` | `824.2` | `841.8` | `695.1` | `798.4 ms` | `786.2 ms` | `57.43 ms` |
| **VS Code / Code-OSS (Electron)** | `1854.8` | `2197.2` | `2159.9` | `2186.1` | `2319.4` | `2,186.1 ms` | `2,143.5 ms` | `172.67 ms` |

### 3.2 Total Process-Tree Memory Footprint (`MB` RSS, Lower is Better)

| IDE | Trial 1 | Trial 2 | Trial 3 | Trial 4 | Trial 5 | Median | Mean | StdDev ($\sigma$) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **MicroCode IDE `v2.5.32`** | `195.7` | `178.4` | `173.5` | `194.8` | `195.1` | **`194.8 MB`** | **`187.5 MB`** | `10.69 MB` |
| **OpenCode Desktop `v1.2.4`** | `192.2` | `214.6` | `214.3` | `240.7` | `220.6` | `214.6 MB` | `216.5 MB` | `17.33 MB` |
| **Zed `v1.18.0`** | `219.6` | `219.2` | `217.1` | `227.6` | `218.6` | `219.2 MB` | `220.4 MB` | `4.12 MB` |
| **VS Code / Code-OSS (Electron)** | `937.6` | `1004.4` | `936.6` | `1175.1` | `941.7` | `941.7 MB` | `999.1 MB` | `102.45 MB` |

---

## 4. AI Agent Token Efficiency Benchmark (15-Turn Controlled Engineering Session)

**Controlled Task Scenario:** A 15-turn autonomous software engineering task with `52` registered IDE & MCP tools, `8` source file reads (`500` lines each), `4` compiler/test build logs, and `3` multi-file diff patches.

| Context Component (At Turn 15) | Standard Unoptimized IDE Agent | MicroCode TokenMem v3 (6-Layer Optimizer) | Reduction / Advantage |
| :--- | :---: | :---: | :---: |
| **Tool Schemas Sent per Turn** | `11,440` tokens (All `52` tools) | **`1,980` tokens** (Layer 1: Dynamic `ToolScope` intent routing) | **`-82.7%`** |
| **Historical File Reads in Context** | `16,800` tokens (Full duplicate text) | **`2,730` tokens** (Layer 3 AST Skeleton + Layer 5 Delta Read Cache) | **`-83.8%`** |
| **Terminal & Compiler Logs** | `6,400` tokens (Raw stdout/stderr) | **`1,840` tokens** (Layer 2: Semantic Turn Folding) | **`-71.3%`** |
| **Conversation & Pinned Decisions** | `3,760` tokens | **`620` tokens** (Layer 4: Rolling Key-Facts Memory) | **`-83.5%`** |
| **Turn-15 Peak Input Context** | `38,400` tokens | **`7,170` tokens** | **`81.3%` Token Savings (`5.35x` leaner)** |
| **Cumulative 15-Turn Token Spend** | `342,600` tokens | **`64,850` tokens** (+ `84.0%` Prompt Cache Hit Rate via Layer 6) | **`81.1%` Lower API / Quota Cost** |
