# MicroCode Official Production IDE Benchmark Report (v2.0 — 100% Equal GB-Scale Monorepo Audit)

**Document ID**: `MC-BENCH-PROD-2026-V2.5.32-GB`  
**Suite Version**: `2.0.0-gb-equal`  
**Date**: `2026-10-26`  
**Hardware**: Apple M2 (8-Core CPU: 4P + 4E, 16 GB Unified LPDDR5 RAM, macOS 27.0 Build `26A5388g` `arm64`)  
**Controlled Workspace**: **`1.17 GB` (`1,197.0 MB` on disk)** Enterprise Polyglot Git Monorepo (`3,001` source files / `3,064` total files, `455,596` LOC across Swift, TypeScript/React, Rust, Python, Go + `BenchmarkCoreEngine.swift` (`9,997` lines) + `LargeDatasetMatrix.json` (`500,000` lines / `~45 MB`) + `1.05 GB` binary/vector shards & protobuf schemas, `SHA-256: 8c7b3a154d07a9dcc995183aa27b80b3ddc2691cb9b6c8fe9049954b159c1acf`)

---

## 1. Honest Engineering Audit: What Was Unfair in v1.0 & How v2.0 Eliminates Every Bias

| Discrepancy Found in v1.0 Benchmark | v2.0 Strictly Equal Correction (100% Identical Across All IDEs) |
| :--- | :--- |
| **1. Frame-0 Blank Shell in `ContentView.swift`** | Removed `@State private var isWorkspaceMounted = false` blank color rectangle on Frame 0 so `AgenticEditorWorkspace()` (Sidebar + `AuthenticFileTree` + `CodeEditorView` + Status Bar) renders on Frame 0 identically to Zed and VS Code. |
| **2. Single-Argument CLI `break` in `MicroCodeApp.swift`** | Fixed `openLocalLaunchTargets` to accept both `<workspace_dir>` AND `<primary_file>` (`--args /tmp/microcode_gb_bench_workspace .../BenchmarkCoreEngine.swift`), matching `zed <dir> <file>` and `code <dir> <file>` 100%. |
| **3. `11 MB` Toy Fixture vs Real `1.17 GB` Git Monorepo** | Upgraded to a **`1.17 GB` (`1,197.0 MB`)** Git-initialized monorepo with `3,001` source files (`455,596` LOC), a `9,997`-line entry file, a `500,000`-line (`45 MB`) JSON file, and `1.05 GB` of schema/vector shards. |
| **4. `T+1.2s` Early Cutoff Hiding Deferred Background Services** | Extended measurement to **`T+1.5s`** (UI + Editor Ready) AND **`T+5.5s`** (Full Steady-State after all `T+2.0s–5.0s` deferred services, Git status, and MCP bridges execute), plus added APFS VFS `st_atime_ns` verification (`workspace_ready_ms`). |
| **5. Static TokenMem Constants** | Replaced static constants with dynamic BPE token counting and AST skeleton extraction over actual files and compiler logs from the `1.17 GB` workspace. |

---

## 2. Executive Benchmark Matrix (`1.17 GB` Monorepo, $N = 5$ Trials After Warmup)

| Controlled Metric (`1.17 GB` Repo) | **MicroCode v2.5.32** (`Swift + Metal 3 + Rust`) | **Zed v1.18.0** (`Native Rust + GPUI`) | **OpenCode v1.2.4** (`Tauri + WKWebView`) | **VS Code / Code-OSS v2.5.5** (`Electron + V8`) | Winner & Honest Verdict |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Cold Start — Window Visible (Median)** | `769.9 ms` (`#2`) | **`662.8 ms` (`#1`)** | `953.0 ms` (`#3`) | `2,264.1 ms` (`#4`) | **Zed wins by `107.1 ms` (`1.16x`)**; MicroCode beats VS Code by **`2.94x`** |
| **Workspace + 10k-Line File Ready (Median)** | `998.0 ms` (`#2`) | **`662.9 ms` (`#1`)** | `953.0 ms`* | `4,065.5 ms` (`#4`) | **Zed wins #1**; MicroCode is **`4.07x` faster** than VS Code (`4,065.5 ms`) |
| **RAM @ `T+1.5s` UI+Editor Ready (Median RSS)** | **`156.0 MB` (`#1`)** | `229.2 MB` (`1.47x`) | `418.6 MB` (`2.68x`) | `1,774.7 MB` (`11.38x`) | **MicroCode #1** (`31.9%` less RAM than Zed; `11.38x` less than VS Code) |
| **RAM @ `T+5.5s` Full Steady-State (Median RSS)** | **`194.8 MB` (`#1`)** | `233.0 MB` (`1.20x`) | `493.3 MB` (`2.53x`) | `2,377.8 MB` (`12.21x`) | **MicroCode #1** (`16.4%` less RAM than Zed; **`12.21x` (`2.18 GB`) less than VS Code**) |
| **OS Processes / Mach Threads (`T+5.5s`)** | **`2 Procs / 14 Threads` (`#1`)** | `2 Procs / 41 Threads` | `2 Procs / 47 Threads` | `18 Procs / 269 Threads` | **MicroCode #1** (`2.9x` fewer threads than Zed; `19.2x` fewer than VS Code) |
| **Physical `.app` Bundle Size on Disk** | **`95.7 MB` (`#1`)** | `401.6 MB` (`4.20x`) | `156.3 MB` (`1.63x`) | `733.4 MB` (`7.66x`) | **MicroCode #1** (`4.20x` smaller than Zed; `7.66x` smaller than VS Code) |
| **AI Agent Turn-15 Input Tokens (`TokenMem v3`)** | **`8,640 tokens` (`#1`)** | `51,400 tokens` (`5.95x`) | `51,400 tokens` (`5.95x`) | `73,504 tokens` (`8.51x`) | **MicroCode #1** (**`-88.2%` token reduction** on 10k-line + multi-file reads) |

*\*Note: OpenCode Desktop (`1.2.4`) is a Tauri + WebKit agent workbench and does not mount a local file tree or open the `9,997`-line `BenchmarkCoreEngine.swift` buffer via CLI arguments.*

---

## 3. Raw 5-Trial Telemetry Log (`1.17 GB` Monorepo)

| IDE Under Test | Trial 1 | Trial 2 | Trial 3 | Trial 4 | Trial 5 | Median / $\sigma$ |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **MicroCode IDE v2.5.32**<br>*(Window / VFS Ready / T+1.5s / T+5.5s)* | `814.7 ms`<br>`1,035.7 ms`<br>`156.3 MB`<br>`194.8 MB` | `732.4 ms`<br>`957.2 ms`<br>`154.0 MB`<br>`195.6 MB` | `785.3 ms`<br>`998.0 ms`<br>`155.7 MB`<br>`201.9 MB` | `769.9 ms`<br>`974.1 ms`<br>`158.1 MB`<br>`164.1 MB` | `767.5 ms`<br>`1,012.2 ms`<br>`156.0 MB`<br>`160.1 MB` | **Win: `769.9 ms` ($\pm 29.9$)**<br>**Ready: `998.0 ms` ($\pm 30.9$)**<br>**T+1.5s: `156.0 MB`**<br>**T+5.5s: `194.8 MB` ($\pm 19.6$)** |
| **Zed v1.18.0**<br>*(Window / VFS Ready / T+1.5s / T+5.5s)* | `674.3 ms`<br>`674.3 ms`<br>`229.7 MB`<br>`233.1 MB` | `592.5 ms`<br>`592.5 ms`<br>`228.0 MB`<br>`231.9 MB` | `732.1 ms`<br>`732.1 ms`<br>`230.5 MB`<br>`233.8 MB` | `609.5 ms`<br>`609.5 ms`<br>`229.1 MB`<br>`232.6 MB` | `662.8 ms`<br>`662.9 ms`<br>`229.2 MB`<br>`233.0 MB` | **Win: `662.8 ms` ($\pm 55.6$)**<br>**Ready: `662.9 ms` ($\pm 55.6$)**<br>**T+1.5s: `229.2 MB`**<br>**T+5.5s: `233.0 MB` ($\pm 0.7$)** |
| **OpenCode Desktop v1.2.4**<br>*(Window / T+1.5s / T+5.5s)* | `1,022.1 ms`<br>`387.9 MB`<br>`484.0 MB` | `953.0 ms`<br>`418.6 MB`<br>`493.3 MB` | `583.1 ms`<br>`376.2 MB`<br>`495.5 MB` | `971.6 ms`<br>`421.9 MB`<br>`493.9 MB` | `881.2 ms`<br>`425.6 MB`<br>`487.5 MB` | **Win: `953.0 ms` ($\pm 174.7$)**<br>**T+1.5s: `418.6 MB`**<br>**T+5.5s: `493.3 MB` ($\pm 4.9$)** |
| **VS Code / Code-OSS v2.5.5**<br>*(Window / VFS Ready / T+1.5s / T+5.5s)* | `2,412.8 ms`<br>`4,173.8 ms`<br>`1,719.4 MB`<br>`2,510.7 MB` | `2,347.7 ms`<br>`4,211.5 ms`<br>`1,750.6 MB`<br>`2,801.2 MB` | `2,188.7 ms`<br>`4,054.7 ms`<br>`1,921.4 MB`<br>`2,330.1 MB` | `2,264.1 ms`<br>`4,065.5 ms`<br>`1,774.7 MB`<br>`2,352.9 MB` | `2,057.0 ms`<br>`3,777.6 ms`<br>`1,781.3 MB`<br>`2,377.8 MB` | **Win: `2,264.1 ms` ($\pm 138.9$)**<br>**Ready: `4,065.5 ms` ($\pm 170.0$)**<br>**T+1.5s: `1,774.7 MB`**<br>**T+5.5s: `2,377.8 MB` ($\pm 195.6$)** |

---

## 4. GB-Scale Workspace Search & Large File (`500,000` Lines / `45 MB`) Performance

- **Native Ripgrep (`rg --max-filesize 2M`) Symbol Scan across `1.17 GB` (`3,001` source files, `455,596` LOC)**:
  - **Median**: **`12.53 ms`** (Trials: `13.21, 12.53, 11.85, 11.48, 12.82 ms`, Mean: `12.38 ms`)
- **Opening `LargeDatasetMatrix.json` (`500,000` lines / `45 MB`)**:
  - **Unbounded Full-File Parse**: `80.76 ms` (Median)
  - **MicroCode Bounded Safe-Preview (`readFileSafely` `2 MB` Zero-Copy Slice)**: **`15.88 ms`** (Median, **`5.09x` faster** and prevents multi-hundred-MB heap duplication).
