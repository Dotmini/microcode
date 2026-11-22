# MicroCode & MicroCode AI for Windows — Port Specification

> **ภาษาไทย (สรุป):** เอกสารนี้คือสเปกสำหรับสร้าง MicroCode และ MicroCode AI บน Windows ให้หน้าตา (UI/UX) ฟีเจอร์ และสถาปัตยกรรมเหมือนเวอร์ชัน macOS ทุกจุด เขียนให้ AI อีกตัว (เช่น Claude) อ่านแล้วลงมือทำได้ทันที ทุกหัวข้ออ้างไฟล์ต้นฉบับใน repo นี้ (`MicroCode/...`) เพื่อเปิดดูพฤติกรรมจริงได้ กฎเหล็ก: ห้าม hard-code ค่าใด ๆ (URL, key, port, client id) ต้องระดับ production ตั้งแต่วันแรก

**Audience:** an engineer or AI agent building the Windows edition from scratch.
**Source of truth:** the macOS app in this repository (branch `main`). Every section cites the Swift/Rust file that defines the behaviour — when this document and the code disagree, the code wins; read it.
**Screenshots:** [`screenshots/`](screenshots/) (see [`screenshots/index.md`](screenshots/index.md)). Each screen section links its capture.

---

## 0. Ground rules (non-negotiable)

1. **Same product, not a re-imagining.** Identical information architecture, labels, icons (mapped), layout proportions, default sizes, keyboard shortcuts (⌘ → Ctrl, ⌥ → Alt, ⌃ → Ctrl+Alt where ⌘ is taken — keep one mapping table, §1.10), states, and copy (including Thai copy where the Mac app uses Thai).
2. **No hard-coding.** No endpoint, port, OAuth client id, model id list, price, or feature flag may be a literal in UI or service code. All of them come from a typed configuration layer (§5.1) with this precedence: *signed remote config → environment variable → user settings file → bundled defaults file*. Secrets never live in source, config files or logs — only in the OS credential store (§5.2).
3. **Production from day one.** Structured logging with redaction, crash reporting, signed builds, auto-update, telemetry opt-in, retries with backoff and timeouts on every network call, cancellation everywhere, no blocking work on the UI thread.
4. **Two editions, one codebase.** *MicroCode* (full IDE) and *MicroCode AI* (standalone agent edition). On Mac the AI edition is the same binary with `AppEdition.isStandaloneAI` (`MicroCode/MicroCodeApp.swift:15`): it forces the Agent surface, hides the mode switcher and hides Settings tabs Editor / Cloud GPU / Extensions. Do the same with a build-time edition flag.
5. **Performance parity** (§1.11): first paint < 1 s, mode switch with no animation, streaming UI updates throttled, no per-frame layout of the transcript.

### 0.1 Suggested Windows technology mapping

Use this if the stack is not decided yet; if it is, keep the *behaviour* and map accordingly.

| macOS piece | Windows equivalent |
|---|---|
| SwiftUI + AppKit hot paths | WinUI 3 (Windows App SDK) + C#/.NET 8, or C++/WinRT for hot paths; Composition API for animation |
| Rust core (`MicroCodeCore/`, `backend/`, UniFFI) | **Reuse as-is**: build the same Rust crates for `x86_64/aarch64-pc-windows-msvc`; bind via UniFFI C# bindings (or csbindgen) — do not rewrite the core |
| Keychain (`KeychainManager`) | Windows Credential Manager / DPAPI (`PasswordVault` or `CredWrite` with `CRED_PERSIST_LOCAL_MACHINE` off) |
| `UserDefaults` | `%APPDATA%\MicroCode\settings.json` (versioned schema, atomic writes) |
| `~/Library/Application Support/MicroCode` | `%LOCALAPPDATA%\MicroCode` (state, transcripts, runtimes) |
| `~/.microcode/` (workspace state, rules) | `%USERPROFILE%\.microcode\` (keep the same layout so `.microcode/` files are portable) |
| SF Symbols | Segoe Fluent Icons (keep one icon-name map file; names in this spec are SF Symbol names) |
| NSMenu (model picker) | `MenuFlyout` built on demand |
| CADisplayLink / Core Animation | `CompositionAnimation`, `Microsoft.UI.Composition` |
| Bonjour (collaboration discovery) | DNS-SD via `Windows.Networking.ServiceDiscovery.Dnssd` |
| `screencapture`, CGEvent (computer use) | Windows Graphics Capture + `SendInput` / UI Automation |
| iOS Simulator / Xcode | Not available on Windows: hide iOS-simulator items; keep Android emulator, web, Flutter, device USB (ADB) |
| `.app` + DMG/PKG, Sparkle-style updates | MSIX (+ App Installer auto-update) or Squirrel/Velopack; code-signed |

---

## 1. UI/UX specification

**Screenshot map** (59 captures from MicroCode 2.5.43, demo workspace, private data redacted — full list in [`screenshots/index.md`](screenshots/index.md)):

| Spec section | Screenshots |
|---|---|
| §1.1–1.2 shell & header | [01 editor](screenshots/01-editor-mode.png) · [02 More Mode](screenshots/02-more-mode-menu.png) · [03 overflow](screenshots/03-overflow-menu.png) · [04 preview](screenshots/04-preview-menu.png) · [39 context inspector](screenshots/39-context-inspector.png) |
| §1.3 sidebars | [08 git](screenshots/08-sidebar-git.png) · [09 search](screenshots/09-sidebar-search.png) · [10 problems](screenshots/10-sidebar-problems.png) · [11 git settings](screenshots/11-git-settings.png) |
| §1.4 editor bottom panel | [05 output](screenshots/05-console-output.png) · [06 terminal](screenshots/06-console-terminal.png) · [07 analysis](screenshots/07-console-analysis.png) |
| §1.5 modes | [27 cells](screenshots/27-notebook-cell-mode.png) · [28 playground](screenshots/28-playground-mode.png) · [29 science](screenshots/29-science-mode.png) · [30 browser](screenshots/30-ide-web-browser.png) · [31 SSH](screenshots/31-remote-explorer-ssh.png) · [32 embed/IoT](screenshots/32-embed-iot-studio.png) · [33 API](screenshots/33-api-studio.png) · [34 extensions](screenshots/34-extension-studio.png) · [35 database](screenshots/35-database-studio.png) · [36 container](screenshots/36-apple-container-studio.png) · [37 CI/CD](screenshots/37-cicd-pipelines.png) · [38 collaboration](screenshots/38-realtime-collaboration.png) |
| §1.6 agent panel | [12 chat](screenshots/12-agent-chat.png) · [13 model picker](screenshots/13-composer-model-picker.png) · [14 + menu](screenshots/14-composer-plus-menu.png) · [15 autonomy](screenshots/15-composer-autonomy-menu.png) · [16 agent mode](screenshots/16-composer-agent-mode-menu.png) · [17 run target](screenshots/17-composer-run-target-menu.png) · [18 plan](screenshots/18-agent-plan.png) · [19 task](screenshots/19-agent-task.png) · [20 more](screenshots/20-agent-more-menu.png) · [21 team](screenshots/21-agent-team-menu.png) · [22 actions](screenshots/22-agent-actions-menu.png) |
| §3.8–3.9 ACP & MCP | [23 agent connections](screenshots/23-acp-agent-connections.png) · [24 rules](screenshots/24-acp-ecosystem-rules.png) · [25 external agents](screenshots/25-acp-external-agents.png) · [26 MCP servers](screenshots/26-acp-mcp-servers.png) · [50 settings MCP](screenshots/50-settings-mcp-servers.png) |
| §1.7 welcome, onboarding, settings | [55 projects](screenshots/55-welcome-projects.png) · [56 templates](screenshots/56-welcome-templates.png) · [57 AI architect](screenshots/57-welcome-ai-architect.png) · [58 onboarding](screenshots/58-first-launch-onboarding.png) · [42 general](screenshots/42-settings-general.png) · [43 editor](screenshots/43-settings-editor.png) · [44 AI & agent](screenshots/44-settings-ai-agent.png) · [51 tools](screenshots/51-settings-tools.png) · [52 extensions](screenshots/52-settings-extensions.png) · [54 about](screenshots/54-settings-about.png) · [59 shortcuts](screenshots/59-keyboard-shortcuts.png) |
| §3.7 skills | [48 skills](screenshots/48-settings-skills.png) · [49 skills (Arc)](screenshots/49-settings-skills-arc.png) |
| §4 accounts & billing | [53 account & license](screenshots/53-settings-account.png) |
| §5 connectivity | [45 connect with phone](screenshots/45-settings-connect-phone.png) · [46 team collaboration](screenshots/46-settings-team-collaboration.png) · [47 cloud GPU](screenshots/47-settings-cloud-gpu.png) · [40 runtime manager / Arc](screenshots/40-runtime-manager-arc.png) · [41 runtimes](screenshots/41-runtime-manager-list.png) |

Not captured: device/simulator docks (no device attached) and a standalone ACP chat window (not reachable in the current UI; ACP is covered by 13 and 22–26).

All paths below are relative to `MicroCode/`. Sizes are points on Mac — use the same numbers as effective pixels (epx) on Windows at 100% scale.

### 1.1 Window and app shell

- One main window. Min content size **1200×800** (hard min 720×480). Centered on first launch. Hidden title bar with content extending into it (`MicroCodeApp.swift:157-273`); on Windows use `ExtendsContentIntoTitleBar` and place the caption buttons on the right; the Mac reserves a 78 px leading inset for traffic lights — on Windows reserve the caption-button width on the trailing side instead. Only explicit drag regions move the window.
- Closing the window hides it (app keeps running). If an AI task is running the taskbar badge shows **AI**. Quitting while AI runs shows a 4-choice dialog: *continue in background / finish then quit / save checkpoint & quit / cancel* (Thai copy, `MicroCodeApp.swift:702`).
- Background = `appTheme.workspaceBackground`; glass themes use a transparent (Mica/Acrylic on Windows) window.
- Root (`Views/ContentView.swift:28-125`): workspace + overlays (auto-healer scrim black 0.3 with bottom sheet; first-launch welcome overlay on top). Settings opens as a modal sheet.

**Three-column workspace** (`ContentView.swift:343-1002`, `NativeSidebarSplitContainer`):

| Column | Default | Range | Behaviour |
|---|---|---|---|
| Left sidebar | 270 | 160–600 | Persisted (`microcode_agentic_sidebar_width`, `sidebarVisible`, 0.25 s debounce). Drag below 95 collapses. Double-click splitter resets to 270. Show/hide = 0.12 s quartic ease-out slide; inner content keeps constant width while clipped (no reflow). Hidden in modes with their own sidebar: Embedded, Browser, API Studio, Remote/SSH, Notebook, Playground. |
| Main column | — | min 320 | 36 px unified header bar + active surface. |
| Right inspector (⌘I) | 380 | 220–640 (760 on Preview tab, 880 if sidebar hidden) | Collapses below 120. Tabs: **Context**, **Preview**, **Plan**, **Tasks** (10 pt labels). |

**Splitters** (`Views/Components/DraggableSplitView.swift`): 6 px hit zone, invisible at rest; on hover/drag accent 0.12 background, 1.5 px accent line, 3×32 grip pill; double-click resets; each has a collapse threshold.

### 1.2 Unified header bar (36 px, `ContentView.swift:1299-1561`)

Width buckets: regular ≥1120, compact 760–1119, tight 540–759, ultra-tight <540 (progressively hide labels → icons only).

Left → right:
1. Leading spacer (caption-button clearance on Mac).
2. Sidebar toggle 28×26 radius 6 ("Hide Sidebar (⌘B)").
3. Agent surface + sidebar hidden: "+" new chat (26×26).
4. Breadcrumb: folder icon + project name (12 semibold) + "/" + task title or file (12 medium), max width 240 (180 compact).
5. Drag region.
6. **Agent surface:** mode pills **Chat | Plan | Task | More ▾** (Plan shows a 5 px orange dot while plan approval is pending). *More:* Walkthrough Summary, Interactive Notebook Cells, Background Worktree Agents, Token & Cost Usage, Diagnostic Logs, Audit Log (Flight Recorder), Consensus Engine. Then **Preview ▾** and **Actions ▾** (Team, Connect External Agents (1-Click)…, Rules, MCP & Context Settings…, Index Project, Export/Import .ARX Capsule…, Undo Last, Clear Chat).
7. **Code surface:** pills **▶ Run** (green 0.12 tint), **Build** (hammer), **Preview ▾**, **Console** (accent when active).
8. Collaboration presence avatars.
9. **Surface switcher** capsule (padding 2, fill primary 0.04, radius 6): **Agent** (brain) · **Code Editor** (curly braces) · **More Mode ▾** (grid) → Playground Mode, Cell Mode (Notebook), SSH Remote Browser, Science Mode, IDE Web Browser, Embed & IoT Studio, API Studio, Extension Studio. Tab style: 11 pt; active semibold with primary 0.10 fill; padding 10/7 × 4; radius 5.
10. `…` layout menu: Run Code, Build Project, Database Studio, API Studio, Container Studio, CI/CD Pipelines, Realtime Collaboration, Auto-Hide Window Controls, Connect with Phone (QR)….
11. Inspector toggle (⌘I).
12. Settings gear (only when the sidebar is hidden).

**Preview popover** (356 wide, "Live Preview ⌥⌘P"): sections *Web & Localhost* (Localhost Dock, Full Browser), *Connected & Active* (iPhone USB, Android USB), *Apple Simulators* (Mac only), *Android Emulator* (AVD runtimes); footer "Choose Device & Run Target…".

### 1.3 Sidebars

**Agent sidebar** (`AgenticWorkspaceSidebar`, `ContentView.swift:2642-3397`), top→bottom:
1. Header 36: "MicroCode" (13 bold) + search toggle → search field 24 ("Search tasks & conversations...").
2. **+ New Conversation ⌘N** (28 tall, radius 7, fill primary 0.065 / 0.11 hover).
3. **WORKSPACES** (10 bold, tracking 0.4) with add-folder and fold chevron. Project rows: chevron, folder icon (filled + accent when active), name 12.5, chat-count badge, "+". Up to 5 chats per workspace then "…". Chat rows 30 px; context menu: Export as .ARX Capsule…, Rename Conversation…, Copy Title, Delete Conversation. Max list height 240 while files are expanded.
4. **WORKSPACE FILES** — file tree.
5. Footer: Settings, Help, Phone (QR icon; becomes "phone + waves" with a pending-approvals count).

**Editor sidebar** (`XcodeEditorSidebar`, `Views/Workspace/WorkspaceXcodeNavigatorAndInspector.swift:14-1140`): 36 px icon strip (24×22 tabs, selected = filled icon + accent): Project Navigator · Source Control (embeds Git panel) · Search in Workspace (ripgrep, case/regex toggles, replace) · Issue Navigator; project header; bottom filter bar with "recent only".

There is **no command palette, no quick-open, and no status bar** in the shipping Mac app — do not add them (the old `StatusBarView` is dead code).

### 1.4 Code editor surface (`Views/Workspace/WorkspaceEditorAndDebugViews.swift:625-2200`)

- Tab bar 30: icon 11, name 12, 6 px dirty dot, close × only on hover/selected, 2 px selection indicator, horizontal scroll.
- Editor (`CodeEditor`) or file preview (image/PDF/spreadsheet). Empty: magnifier-doc icon 48 + "Select a file to view". `.ipynb` shows a convert-to-cells banner.
- Inline Edit **⌘K**: Accept (⌘↩) / Reject (Esc).
- **Bottom panel** (`DebugArea`): default 240 (`mc_debug_area_height`), 130–520 via 4 px handle, maximize toggle. Header 28 with tabs **OUTPUT | TERMINAL | PROBLEMS (badge) | ANALYSIS** + actions Fix with AI, +, split, refresh, trash, maximize, close. Problems empty: seal-check + "No problems detected in workspace".

### 1.5 Modes (`Models/AppState.swift:789-835`, `EditorMode`)

| Mode | Label / icon | Shortcut | Screen (file) |
|---|---|---|---|
| `code` | Code Editor / doc.text | Ctrl+Alt+1 (⌃1) | §1.4 |
| `aiAgent` | AI Agent / brain.head.profile | ⌃2 | §1.6 |
| `notebook` | Notebook (Cell Mode) / book.pages | ⌃3 | `Views/NotebookView.swift:2487` |
| `playground` | Playground / play.rectangle | ⌃4 | `Views/PlaygroundView.swift:103` |
| `science` | Science Mode / atom | ⌃5 | `Views/ScienceModeView.swift` |
| `browser` | Browser / globe | ⌃6 | `IDEBrowserView.swift` |
| `remoteX` | Remote Explorer (SSH) / server.rack | ⌃7 | `RemoteXView.swift:655` |
| `embedded` | Embed & IoT Studio / cpu.fill | ⌃8 | `EmbeddedStudioView.swift:453` |
| `apiClient` | API Studio / network | ⌃9 | `APIClientView.swift` |
| `extensions` | Extension Studio / puzzlepiece.extension | ⌃E | `ExtensionStudioView.swift` |
| (welcome) | Welcome Dashboard | ⌃0 | `WorkspaceWelcomeAndSheets.swift:21-650` |
| `scenario` | Scenario / flowchart | — (not reachable from menus) | `ScenarioView.swift` |

Mode switches disable animation and close the welcome home (`switchToMode`, `AppState.swift:5651`). Database Studio, CI/CD, Container, Collaboration are **sheets**, not modes.

- **Cell / Notebook:** 3 columns — sidebar "Cell Sheets" + kernels (CLOUD COMPUTE; LOCAL / APPLE SILICON — on Windows: LOCAL / CUDA-DirectML) + Data Files + Shared Data (min 180, draggable); center cells (min 320); Notebook Agent panel (≤560). Toolbar: name, **DAG**, Colab, SSH, **Auto ENV**, GPU wallet, **Vars**, **App** (presentation), execution count, **Agent**. Capsule `[ + | ▶ | ▶▶ ▾ ]` = Add / Run Selected / Run All / Run by Color-Tag (Clear Outputs, Restart Kernel). Formats `.mcnb`, `.ipynb`, `.mic`. Ctrl+S / Ctrl+Shift+S.
- **Playground:** toolbar language menu, settings popover (font size/family/theme), **Editor / Cell Mode** segmented, "n cells", Run All, Add, Open/Save `.microplay`, toggles Document/Data/Output/Preview/Hot Reload; Run = Ctrl+R. Layout: optional document viewer (0.3), editor + Data Files (0.55), GUI preview (device frames) over Output.
- **Science:** header "Science · Research workspace" + AlphaFold, MedGemma, Analyze in Cells, "Research use" chip; panel picker Project/Structure/Results/Paper; split = agent (science scope, min 420) | artifact panel (min 360).
- **SSH Remote Explorer:** split 0.28 — "REMOTE SERVERS (n)", import `~/.ssh/config`, +, search | connection tabs Terminal / Files / Info. Empty state with Add Remote Server, Import, Quick Cloud Presets (AWS, GCP, Alibaba, DigitalOcean, RunPod, Azure). Server sheet: Smart SSH Import, Provider, Connection Type (SSH/SFTP/FTP/FTPS), Name, Host, Port, password or key.
- **Embed & IoT Studio:** left 270 (Ctrl+Shift+L) | tool (min 320) | AI panel (Ctrl+Shift+A); UPPER-CASE labels. Tools (Ctrl+1–5): Embedded Sketch & IDE, Serial Terminal & Raw Hex, High-Speed Sensor Plotter, Interactive GPIO Pinout, ELF Memory & Symbol Map, Flash Memory & Partitions, Hardware Flasher, Crash & Panic Decoder, Wireless OTA, BLE GATT. Buttons COMPILE ONLY, RUN DIRECT TO BOARD, AI AUTO-FIX, DECODE CRASH, BAUD. Empty: "NO HARDWARE DETECTED" + SCAN USB PORTS.
- **IDE Web Browser:** tabs, "Search or enter URL", bookmarks, multi-point element picker ("Send All (n)" to the agent), devtools console/network (WebView2 on Windows).
- **API Studio:** "API Studio · 100% Native" + Scan Routes, Load .env, Code Snippet, Exit to Code; history sidebar; "Enter URL or paste cURL"; Send; body JSON/XML/Text/Form; auth Token/User.
- **Extension Studio:** Open VSX Marketplace / Installed (n), Install .VSIX; list 380 + detail (Install, README).
- **Device dock** ("Live Preview & Device Hub", Alt+Ctrl+P): tabs, Android picker with Back/Home/Recents/send-text, Flutter Hot Reload (ms readout); width 460 default, min 240; chat keeps ≥46%.

### 1.6 AI agent panel (`Views/AI/*`) — the most important screen

- **Layout** (`AIAgentView.swift:708-967`): [optional chat list 160–380, off in the unified shell] | main column (Chat, or Task editor, Walkthrough, A4 Paper, Cell mode) | Plan side panel 260–680 (default 400; becomes full column below 820 available) | device dock. Drag-and-drop of files/PDF/images anywhere.
- **Empty state:** composer centered, max width 880, padding 28; project pill (folder + name + chevron → project selector) above it; optional "Where Was I?" briefing card, status HUD, failover / secret-leak alert bars. Suggestions: "Explain this code", "Find bugs in my project", "Refactor for performance", "Write unit tests" (Science has its own four).
- **Transcript** (`AIAgentChatStageAndCells.swift:1446`): virtualized list (LazyVStack ↔ `ItemsRepeater`/`ListView` with virtualization), equatable rows; "Load earlier messages" paging; auto-scroll to bottom throttled to ≥0.14 s, paused when the user scrolls up; floating "↓ Latest messages" pill.
- **User bubble:** right-aligned, max 620, padding 14×10, radius 14, fill primary 0.095 dark / 0.065 light, stroke 0.14/0.10 @0.8; collapses after 14 lines ("Show all (n characters)"); context menu Edit & Resend, Revert to Here, Copy, Delete.
- **Assistant message:** no bubble, left, max 880, padding 12; markdown + TeX + tables + HTML blocks + code blocks (`NativeCodeBlockView`); context menu Copy Response, Regenerate, Revert Turn & Files, Delete.
- **Queued message:** orange 0.14 fill / 0.35 stroke, clock icon, Thai "in queue (will auto-send)", Send Now / Cancel; strip above composer "n messages queued:" + Steer Now.
- **Thinking & tools** (`AIAgentTimelineAndMenus.swift`): collapsible "Thought for Ns ›" (placeholder "Formulating reasoning steps…"); live card "Agent Working • Ns" + red LIVE dot + current command (mono); tool timeline "{headline} · n steps" with past-tense rows: Analyzed {file}, Edited {file}, Ran {cmd ≤64}, Searched {q ≤44}, Listed {dir}, Previewed {action}, Executed {tool}. Streaming dots (`AIStreamingThreeDotsView`): 6 px dots, 5 spacing, sine wave scale 0.72–1.08, opacity 0.25–1, lift 2.2, speed 4.6, phase step 0.72 — **compositor-driven, never per-frame layout**.
- **Proposed-change card** (`PendingChangeCard`): file, green +N, red −N, description; Split Diff / Show-Hide Diff; unified diff mono 11.5, line numbers 10, hunk headers cyan, add rows green 0.15/0.12, delete rows red 0.14/0.10; per-hunk "n✓ n✗ n pending", Accept / Reject, Simple View; final "✓ Applied" / "Reverted".
- **Tool approval card** (`ToolApprovalView.swift`): "Permission Required", risk badge SAFE / MODERATE / DANGEROUS / CRITICAL, tool chip, args ("+n more parameter(s)..."), **Reject / Always Allow / Approve (Enter)**, radius 9 on acrylic.
- **Plan review:** "Implementation Plan", "n/m steps completed (x%)", sections Open Questions & Decisions / Proposed Changes / Verification Plan; waiting state "Plan Review Required" with **Reject** and **Approve Plan & Proceed (Ctrl+Enter)**; empty "No Implementation Plan Active" + Load task.md / Draft Plan (/plan).
- **Composer** (`inputCardView`, `AIAgentView.swift:3171`): padding 12×9, radius 14, fill white 0.04, stroke primary 0.10 / 0.24 focused / 0.45@1.5 on drag; drop hint "Drop PDF, Code, Images, or Folders to attach instantly"; attachment and @context chips; auto-growing editor 24–240; Enter sends; placeholder "Ask anything, @ to mention, / for commands — paste (⌘V) or drop files" (short form under 920 wide). Bottom row (3 responsive fallbacks):
  1. **+** menu: Add Files, PDF, Code or Images…; Paste Attachment; Mention Active File; Plan Mode (/plan); Code Review (/review); Connect External Agents…; Rules, MCP & Context Settings….
  2. **Model picker** "{mode badge} · {model}" or "Connect AI" (64–220 wide) → menu sections: Dotmini Cloud · Subscription (Chat / Image / Video / Music) · BYOK & Smart Routers · Local LLM (Ollama, LM Studio, MLX→on Windows: Ollama, LM Studio, llama.cpp/DirectML) · Enterprise API (Vertex, Azure, Bedrock, LiteLLM) · "Enter Custom Model ID...". The list comes from the model catalog (§3.6), **never from literals in the view**.
  3. Scope-lock pill; target environment (local vs SSH/cloud).
  4. **Approval mode pill** (`Models/ToolApprovalModels.swift:4`) "Agent Tool Autonomy": **Safe** (orange, lock-shield, "Ask before every tool execution") · **Smart** (accent, brain, "Ask only for dangerous operations") · **Full Auto** shown "Auto" (green, flame, "Never ask, auto-approve everything").
  5. Sub-agent picker; mic (26 circle, red 0.18 while listening); Send (26 accent circle, arrow-up); while running: "+ Add to Queue" / "Send Immediately"; Stop (26 red 0.85 circle with 8 px white rounded square).
- **Slash commands** (`Services/SlashCommandService.swift:5`): /file /compact /clear /model /explain /fix /test /refactor /review /learn /arx /compare /squad /pns /search /terminal /help /plan /task. Popup rows 34, max 6 visible, radius 8, `/cmd` mono 12.5 semibold + description 11.5 + optional "arg" chip, selected accent 0.14. `@` opens context providers.

### 1.7 Welcome, onboarding, settings

- **Welcome** (`WorkspaceWelcomeAndSheets.swift:21-650`): left rail 210 — "MicroCode" 18 bold + badge; tabs Projects / Templates / AI Architect / Settings (13 pt, radius 8); footer "Apple Silicon Native" → Windows: "Native x64/ARM64", "LSP Services Active". Projects: "Welcome to MicroCode" + cards (38 icon tile, title 13 semibold, subtitle 11, min height 110, radius 12, hover scale 1.015/0.15 s): New Project, Open Folder, Clone Repo, New Playground Mode, New Cell Mode, SSH Remote Browser, Embed & IoT Studio, AI Architect, IDE Web Browser, Settings & Cache; "Recent Workspaces" (empty: "No recent projects found"). Templates: Next.js 14, Vite+React, FastAPI, Rust Axum, SwiftUI (→ WinUI on Windows), Ardium CoreUI, Express, Go Gin, Flutter, Spring Boot 3, PyTorch, Docker, Vue 3, NestJS — template list must be data (JSON), not code.
- **First launch** (`FirstLaunchWelcomeView.swift`): black 0.72 scrim; card 500 wide, padding 28, radius 14, shadow 28; "Welcome to MicroCode" (25 semibold) + three bullets; "SIGN IN — OPTIONAL": **Continue with Google** (38 tall), "Dotmini ID" expander (Email, Password, "Sign in with Dotmini ID"); footer "Continue without signing in". Shown until `%LOCALAPPDATA%\MicroCode\.welcome_done` exists.
- **Settings** (`WorkspaceSettingsAndWindowModifiers.swift:41-258`): modal 880–1240 × 600–920 (ideal 1000×700); sidebar 236 with "‹ Back to app", rows 13 pt radius 7 (selected primary 0.09, hover 0.045), footer "© 2025 MicroCode · Dotmini Software"; content header title 20 bold + **Cancel** (Esc) / **Save Changes** (Enter); padding 32; section headers 11 bold uppercase. Tabs in order: General · Editor · **AI & Agent** (default) · Connect with Phone · Team Collaboration · Cloud GPU · Skills · MCP Servers · Tools · Extensions · Account & License · About (contents in §§3–5).
- **Sheets:** Runtime Manager (Ctrl+Shift+R, 550×500, runtime cards + Arc toolchain card), Commit (⌘K), New File (language grid), SubAgent Monitor ("SubAgent Process Monitor", Kill All), Keyboard Shortcuts (⌘/), Collaboration ("Team Collaboration": NAME, Start Host Session, Join via invite link/room code, LAN-discovered list, ROOM ACCESS CODE), Database Studio (min 900; connections 260; "Connect to a Database"; Ctrl+Enter runs), Agent Ecosystem (External Agents / Platform Rules / MCP Servers / Context Bridge / Inference Models), Agent Connections wizard (agent cards, "1-Click Connect", enterprise hub, local gateway), ACP chat (min 400×500, permission rows).

### 1.8 Design system

- **Themes:** `enum AppTheme` (`Models/AppState.swift:77`), 36 themes, default **dark**; each theme declares light/dark, editor background hex (e.g. VS Code #1E1E1E, Dracula #282a36, GitHub Dark #0d1117, Nord #2E3440, Tokyo Night #1A1B26, Catppuccin #1E1E2E, Solarized #002B36/#FDF6E3, Gruvbox #282828, Navy #0D1B2A) and syntax colors (lines 328-626). Port the theme table as a JSON resource generated from the Swift enum — one source.
- **Surfaces:** `workspaceBackground` pure black for dark; `panelBackground` = editor bg blended 3.5% to white (dark) / 2.5% to black (light), dark = white 0.02; `elevatedBackground` 7% / 4.5%, dark = white 0.10.
- **"Formal monochrome":** chrome drawn with the foreground color at low opacity (common: 0.03, 0.04, 0.05, 0.06, 0.08, 0.10, 0.12). Active fill 0.10 (stroke 0.16–0.20), hover 0.045–0.11, rest 0.04–0.065. Color only carries meaning: green = run/additions, red = deletions/stop, orange = queue/pending/Safe, accent = focus/selection/send. No neon/purple/sparkle decoration.
- **Type:** UI = system font (Segoe UI Variable on Windows); sizes in use 8–13 (11 most common); section labels 10–11 bold uppercase tracking 0.4. Defaults: editor mono 16 (SF Mono → Cascadia Mono), agent "SF Pro" 16 (→ Segoe UI Variable 16), playground mono 13 regular, cell mono 13. Shortcut hints mono 9–9.5.
- **Radii:** 4, 6, 8, 5, 3, 10 (cards 8–12; composer/bubbles/onboarding 14; pills/buttons 5–6; settings rows 7). **Controls:** header icon buttons 28×26, secondary 24×24, pills 4 vertical padding.
- **Motion:** ease-in-out 0.12–0.18 s; hover ease-out 0.15 s; **mode switches never animate**.

### 1.9 Global shortcuts (`MicroCodeApp.swift:771-1060`)

| Area | Mac | Windows |
|---|---|---|
| File/tabs | ⌘, ⌘N ⌘⇧N ⌘O ⌘⇧O ⌘W ⌘⌥W ⌘⇧W ⌘] ⌘[ ⌘S ⌘⇧S | Ctrl+, Ctrl+N Ctrl+Shift+N Ctrl+O Ctrl+Shift+O Ctrl+W Ctrl+Alt+W Ctrl+Shift+W Ctrl+Tab/Ctrl+Shift+Tab (also Ctrl+PgDn/PgUp) Ctrl+S Ctrl+Shift+S |
| Code | ⌘R Run, ⌘⌥Y Debug, ⌘⇧B Build, ⌘. Stop, ⌘⇧F/⌘⇧H find/replace in workspace, ⌘⌥F Format, ⌘⌥R Refactor with AI, ⌘⌥E Explain, ⌘⌥A Analysis, ⌘K Inline Edit | Ctrl+R, Ctrl+Alt+Y, Ctrl+Shift+B, Ctrl+. (and Shift+F5), Ctrl+Shift+F/H, Shift+Alt+F, Ctrl+Alt+R, Ctrl+Alt+E, Ctrl+Alt+A, Ctrl+K |
| View | ⌘B ⌘I ⌘J ⌘⌥G ⌘⌥P ⌘/ ⌘+ ⌘- ⌘0 ⌘L ⌘⌥T | Ctrl+B Ctrl+I Ctrl+J Ctrl+Alt+G Ctrl+Alt+P Ctrl+/ Ctrl++ Ctrl+- Ctrl+0 Ctrl+L Ctrl+Alt+T |
| Modes | ⌃0–⌃9, ⌃E (aliases ⌘⌥1–9) | Ctrl+Alt+0–9, Ctrl+Alt+E |
| Git | ⌘⌃R refresh, ⌘K commit (in Git panel), ⌘⇧P push, ⌘⌥P pull | Ctrl+Alt+F5, Ctrl+Enter in commit box, Ctrl+Shift+P, Ctrl+Alt+L |

Known Mac collisions to resolve, not copy: ⌘⌥P (Pull vs Device Dock), ⌘K (Commit vs Inline Edit). On Windows: Device Dock = Ctrl+Alt+P, Pull = Ctrl+Alt+L, Inline Edit = Ctrl+K, Commit = Ctrl+Enter inside the commit box. Keep all bindings in one remappable keymap file.

### 1.10 Performance conventions (copy these)

- Streaming text → UI at most every **95 ms** (145 ms above 2 KB, 210 ms above 8 KB); the first chunk renders immediately (`Services/AgentService.swift` `pushStreamingToken`). Auto-scroll ≤ 1 per 0.14 s.
- Virtualized, diff-friendly transcript rows; cache rendered markdown and diffs; hover state must not re-render message content.
- Animations on the compositor (Composition API), never a per-frame layout of the chat (on Mac a `TimelineView` re-laid out the whole transcript 120×/s even when hidden — the reason `AIStreamingThreeDotsView` uses Core Animation).
- Splitters/sidebar animate by moving visuals, not by re-running layout of the content; pixel-snapped.
- Small, isolated state stores (sidebar state, header state) so one change does not invalidate the whole app state; persist with 0.25 s debounce.
- Deferred startup: overlays after 2.5 s, phone/LLM servers after 3 s, device refresh after 4.5 s, background startup after 2 s.
- Menus (e.g. model picker) built on open, nothing held while idle. Composer grows 24→240 then scrolls.

---

## 2. System architecture

```
┌──────────────────────────── MicroCode.exe (UI process, WinUI 3) ─────────────────────────────┐
│ Shell & modes (§1) · Agent runtime (§3) · Tool box · Skills · MCP client · ACP host           │
│ Providers/AIClient · Accounts & billing (§4) · Local servers (§5): MCP bridge, subscription   │
│ gateway, phone companion, LLM gateway, collaboration                                          │
│   │ UniFFI (in-process)          │ HTTP+WS on loopback (token)        │ stdio JSON-RPC          │
└───┼──────────────────────────────┼────────────────────────────────────┼─────────────────────────┘
    ▼                              ▼                                    ▼
 microcode_core (Rust)        microcode-backend.exe (Rust, axum)     microcode-mcp.exe (Rust)
 fs_editor, rag_engine,       files, git, code analysis/highlight,   stdio MCP server for external
 llm_client (ghost text),     code runner sandbox, SQL/dataframe,    agents (Claude Desktop, Claude
 kernel power/network         project detect/build/run/test,         Code, Omni AI …)
                              agent-kernel runs, remote SSH/SFTP,
                              preview, telemetry, MCP gateway
```

- **Reuse the Rust crates** (`backend/`, `microcode_core/`, `backend/src/bin/microcode_mcp.rs`) — they are platform-neutral Rust; build them for Windows targets and fix only OS-specific code paths (PTY via ConPTY through `portable-pty`, paths, process trees).
- **Backend process** (`MicroCode/Services/BackendService.swift:15-73`): spawned by the UI, bound to `127.0.0.1` on a *configured* port (Mac default 3000; 3001 for the AI edition so both editions can run), per-launch token `MICROCODE_LOCAL_API_TOKEN` (≥32 random bytes) sent as `X-MicroCode-Token`, `MICROCODE_PARENT_PID` so it exits with the UI (Windows: Job Object with `KILL_ON_JOB_CLOSE`). The backend checks loopback `Host`, origin allow-list and the token (`backend/src/local_auth.rs`). Prefer a random free port written to a 0600-equivalent file (ACL to the current user) over a fixed port.
- **Key backend routes** (`backend/src/main.rs:107-470`): `/health`, `/ws/terminal`, `/api/files/*`, `/api/git/*`, `/api/code/analyze|format|highlight`, `/api/ai/*` (incl. `/api/ai/embedding`), `/api/run/execute|stream|stop/:id`, `/api/sql/execute`, `/api/dataframe/*`, `/api/project/detect|build|run|test`, `/api/agent/*`, `/api/agent-kernel/runs*`, `/api/preview/*`, `/api/remote/*` (SSH/SFTP + `ws …/api/remote/shell/<id>`), `/api/tasks/*`, `/v1/telemetry/events`, `/v1/mcp` gateway.
- **UniFFI `microcode_core`** (`microcode_core/`, Swift bindings in `MicroCode/Services/MicroCore/`): `MicroCore.applyEdit/readFile/writeFile/executeCommand/indexProject/semanticSearch/getIndexStats/clearIndex`, `fetchGhostText`, kernel power/network status. Generate C# bindings with `uniffi-bindgen-cs`.
- **Headless entry points** (same exe, flags): `--acp-server [--workspace <path>]` (MicroCode as an ACP agent over stdio, stdout reserved for NDJSON), `--pns-daemon [--pns-port N]`, and the diagnostic/eval env triggers (`MICROCODE_CLOUD_PROBE_OUT`, `MICROCODE_SUB_PROBE_OUT`, `MICROCODE_SKILLS_DUMP_OUT`, `MICROCODE_AGENT_EVAL_CASES` + `MICROCODE_AGENT_EVAL_OUT`). Keep all of them.

---

## 3. AI system

### 3.1 Agent runtime (`MicroCode/Services/AgentService.swift`)

- **Two scopes**, fully separate chats/workspaces/memory: `editor` (software) and `science` (`AgentSessionScope`, `:25`).
- **Chats:** metadata list (`ChatSession`: id, name, projectPath, projectName, activeSkillIds, messageCount, summaryThroughMessageID, activePlan, createdAt, updatedAt) in settings; messages one JSON file each: `ChatTranscripts/<scope>/<chatId>/manifest.json` + `messages/<messageId>.json` (`AgentTranscriptStore.swift`). Persisted message = `{id, role, content, timestamp, toolResults[{toolCallId, toolName, success, output, stringParams}], attachmentHistoryContext, attachments, turnTelemetryLabel, harnessTrace}` — keep this schema byte-compatible so `.arx` capsules and transcripts move between Mac and Windows.
- **Concurrency:** several chats can run at once (one run per chat); messages sent to a busy chat are **queued** and auto-sent (UI §1.6). Per-run context (workspace root, chat id, scope, plan gate) is carried explicitly (Swift TaskLocals → C# `AsyncLocal`).
- **RAM window:** 24 resident messages, paged by 20; evicted ranges are summarized (`memoryService.summarizeChat`).
- **Turn flow:** prepare user turn (attachment digest, memory store, auto-title "New Task/Task…/Chat…") → resolve provider/model (§3.6) → choose tools (§3.4) → build system prompt (§3.3) → compress history → loop: stream model → run tool calls → feed results back → until the model answers without tool calls → persist assistant message with `harnessTrace` (provider, model, iterations, interventions, end reason).
- **Loop design for Windows — follow the research, not the legacy heuristics.** Internal research (2026-11-21, 197 real agent chats) showed the Mac harness overrides the model in ~10 places (forced fallback tool calls, "CRITICAL" nags, per-batch directives, keyword classifiers) and that this makes the agent *less* capable. Implement the Claude-Code-style loop: the model decides when it is done; the harness executes tools, returns real results, and intervenes only for (a) max-token continuation (≤2), (b) context-overflow compaction, (c) provider failover/retry with backoff, (d) one neutral "claim vs evidence" check (the answer claims a run/export/edit that no tool result in this turn shows), (e) stall breakers (same failing call 5×, same batch 4×, A/B oscillation over 6 batches), (f) user stop. Keep `FollowUpIntent` (`Services/AgentCore/FollowUpIntent.swift`): "run/build/test" act on existing work, "ไหน/where" re-verifies and shows evidence, "ต่อ/continue" resumes.
- **Limits:** iteration cap 128 (user setting, min 24; unlimited in Full Auto). Stream watchdog: 180 s to first token (360 s media models), 90 s idle mid-stream. Tool timeout 600 s. Retries: rate-limit backoff `min(3n,30)` s up to 8; other transient `min(2n,12)` s up to 5; permanent 4xx not retried.
- **Memory** (`AgentMemoryService.swift`): ≤512 memories, 7-day half-life; recall score 0.40 semantic + 0.25 keyword + 0.20 recency + 0.15 importance; embeddings from backend `/api/ai/embedding` with a local hash-embedding fallback; recall is project-scoped and must exclude the current chat (it is already in history).
- **Agent kernel** (Rust, `backend/src/agent_kernel.rs`; client `Services/AgentKernelClient.swift`): durable runs `POST /api/agent-kernel/runs`, `/runs/:id/observe|plan|cancel`; directives continue/retry/replan/verify/complete/stalled. Non-blocking (120 ms request timeout, 120 s offline back-off). Runs persist under the app data dir (`MICROCODE_AGENT_KERNEL_DIR` override).

### 3.2 Project memory and rules

- Managed per-workspace state dir: `~/.microcode/workspaces/<sanitizedName≤40>-<hash12>/` holding `agent.md`, `task.md` (minimal: objective + empty Plan — `Services/AgentCore/AgentTaskFile.swift`; **never** a generic checklist), `mcp.json`, `skills/`. `<ws>/.microcode/<file>` wins when it exists (`WorkspacePathPolicy.swift:193-240`).
- Project instructions read once (dedupe!): `AGENTS.md`, `CLAUDE.md` (+ `.claude/CLAUDE.md`, `@path` imports), `.cursorrules`, `.cursor/rules/*.mdc`, `.windsurfrules`, Cline/Copilot/Zed rule files, `.microcode/rules.md`, `.microcode/project.md`, `MICROCODE.md`, global `~/.microcode/rules.md`; 8,000 chars per file (`ProjectMemoryService.swift`, `MultiPlatformRulesEngine.swift`).
- Workspace config files that execute code (hooks, MCP servers) require **Workspace Trust** before use.

### 3.3 System prompt layout (`buildSystemPrompt`, `AgentService.swift:644`)

Stable prefix (cacheable): persona (software or science) → `## Provider Harness Contract` (per-provider tool-calling instructions). Then the boundary marker `\n\n<!-- microcode:dynamic-context -->` (`AISystemPromptLayout`, `Services/AIStreamPrimitives.swift`). Dynamic part: `## Editor` (file, language, line, selection ≤500 tokens, ≤10 diagnostics, last 5 files) · `## Active Project Workspace` · semantic context · `## Memory` · rolling summary · PNS augmentation · team task · `## agent.md` (≤1,500 tokens) · `## task.md` (≤900, only for multi-step work) · project rules · skills snippet (§3.7) · MCP summary · swarm blackboard · pinned constraints/locked files. Target total ≤ ~20K chars (the Mac prompt is 50–70K chars with duplicated project files). Anthropic: `cache_control` on the stable prefix, the last tool definition and the last message block. Text-bridge providers with a hard size limit must budget by priority (tools → workspace context → persona), never cut the tail (`TextBridgeContextBudget`).

### 3.4 Tools (`Services/AgentCore/AgentToolBox.swift`)

Execution pipeline per call (`execute`, `:316-608`): plan-mode gate → reject invalid JSON args with a precise error → alias normalization (`read_file/cat→file_read`, `bash→shell`, `str_replace→replace_in_file`, `glob→file_search`, `mv→rename_file`, `*_pdf→export_pdf`) → default path = workspace → resolve + sandbox check (writes only inside the workspace; reads may go outside) → approval (§3.5) → enterprise command firewall → **file freshness guard** (edits fail if the file changed on disk since the agent read it; `FileFreshnessGuard.swift`) → detokenize vaulted secrets (never for `shell`) → scope lock → auto checkpoint (`AutoCommitService`) → 3 s read cache → run (600 s) → output through the privacy vault → after mutations: invalidate caches, reload open editors, secret-leak audit, post-edit syntax check. Read-only calls in one batch run in parallel; others sequentially.

| Group | Tools |
|---|---|
| Files & search | `file_read` (path, start_line, end_line; PDF/DOCX/XLSX/ipynb/OCR), `multi_file_read`, `file_write`, `replace_in_file`, `multi_replace_in_file`, `patch_file`, `apply_patch` (V4A or unified diff), `create_directory`, `rename_file`, `grep_search`, `file_search`, `find_symbol`, `codebase_search`, `list_directory_tree`, `repo_map`, `git_status`, `web_fetch`, `attachment_read` |
| LSP | `get_diagnostics`, `lsp_hover`, `lsp_definition`, `lsp_completions`, `lsp_diagnostics`, `lsp_status` |
| Run | `shell` (command, cwd, timeout, is_daemon — dev servers detected and run as daemons; on Windows run through `pwsh`/`cmd` per user setting with ConPTY), `playground_run` (25+ languages), `ardium_run` (Arc 3 `.ar`, 120 s), `cell_list/read/create/update/delete/run` |
| Documents | `inspect_image`, `extract_pdf`, `openthai_ocr`, `export_pdf` (A4 vector PDF with Thai fonts; params path, markdown or source_path, title, subtitle, organization, document_id) |
| Planning & agents | `agent_plan` (set/complete), `create_plan`, `define_subagent`, `invoke_subagent` (type_name, role, prompt, model, owned_paths, wait_for_completion), `manage_subagents`, `send_message`, `swarm_orchestrator` (ceo_squad, acp_dream_team, arena_race, post_fact, read_blackboard, adversarial_review, parallel_swarm, status), `background_agent` |
| Device & UI | `device_runtime` (status, list_devices, start, run, stop, tap, swipe, text, key, install, screenshot — adb on Windows), `preview_control` (open, close, reload, set_url, switch_mode, set_viewport, status), `ide_browser`, `editor_control`, `visual_regression`, `computer_use` (observe with Set-of-Mark, click/drag/scroll/type/shortcut/zoom/wait_for/batch/qa_verify; denylist credential/settings apps), `agent_desktop` |
| Studios & media | `api_studio`, `database_studio`, `science_inspect`, `alphafold_input_validate`, `generate_image/video/music`, `voice_coding` |
| Platform | `skill_engine` (§3.7), `slop_check`, `mcp_orchestrator` (status, discover, connect, configure, search_tools, authenticate, restart, synthesize), `pns_nervous_system` |
| Embedded | `embedded_list_hardware`, `embedded_compile`, `embedded_flash`, `embedded_serial_capture`, `embedded_serial_send`, `embedded_decode_crash` |
| Dynamic | `mcp__local__<tool>` (bundled MCP server), `mcp__<server>__<tool>` (external MCP) |

**Tool tiers** (`ToolScope.swift`): core, navigation, editing, planning, lsp, mcp always; device, execution, science, multimodal, studio, embedded added by intent (English + Thai keywords) or attachments; a call to a tool outside the active tiers widens the scope. Keep the per-run tool list stable (prompt cache). Target ≤ ~20 default tools / ≤12 KB of schemas; load the rest on demand.

**Hooks** (`MultiPlatformRulesEngine.swift:644-805`): read `.microcode/hooks.json`, `.claude/settings.json`, `.claude/settings.local.json`, `.cursor/hooks.json`; stages `pre_tool`/`PreToolUse`, `post_tool`/`PostToolUse`, `pre_finish`/`Stop`; entry `{matcher|glob|tool, command, blockOnFailure=true}` or Claude-style nested `hooks`; run with the user shell, cwd = workspace, 15 s timeout, env `MICROCODE_HOOK_STAGE`, `MICROCODE_WORKSPACE`, `MICROCODE_TOOL`, `MICROCODE_FILE`; non-zero + blocking ⇒ block and return feedback to the model.

**Privacy guard** (`AgentPrivacyGuard.swift`): detect JWTs, `sk-…`, `sk-ant-…`, `AIza…`, GitHub tokens, AWS keys, bearer tokens, private keys, DB URLs, `api_key=`/`password=`; replace with `<VAULT_<TAG>_<n>>` before text leaves the app and restore inside tool calls; `[REDACTED_SECRET_FOR_PRIVACY]` in persisted files; refuse writing secrets into `.microcode/`.

### 3.5 Approval and plan mode

- **Approval modes** (`Models/ToolApprovalModels.swift`): `safe` (ask every tool), `smart` (default; ask unless risk is safe), `yolo`/Full Auto. **Risk:** critical (shell containing destructive patterns such as `rm -rf`, `drop` — on Windows also `Remove-Item -Recurse -Force`, `rd /s`, `format`), dangerous (shell, adb_shell, delete_file, drop_table, computer_use, agent_desktop, execute_code, `skill_engine.run_script/crystallize`, `mcp_orchestrator.connect/configure/synthesize/create`), moderate (file_write, patch_file, replace_in_file, execute_sql, default), safe (file_read, get_diagnostics, list_directory_tree, grep_search, find_symbol). Approval identity is per action for multi-action tools. FIFO queue; unanswered requests auto-reject after 60 s; "Always Allow" per tool identity.
- **Plan mode** (`AgentCore/PlanModePolicy.swift`): prompt contains `[PLAN MODE` → only read-only tools (+ read-only actions of skill/mcp/swarm tools, read-only shell, `mcp__*` whose leaf starts with get/list/search/read/fetch/query/find/describe/view/lookup) until the user approves the plan from `create_plan`. Plan states pending/approved/rejected/modified; step states pending/in_progress/completed/failed/skipped (`Models/ImplementationPlanModels.swift`).

### 3.6 Providers, routing, failover

- **Key modes** (`aiKeyMode`): `cloud` (Dotmini Cloud gateway, §4.2), `subscription` (§4.3), `direct` (BYOK), `local` (§5.3), `enterprise` (§4.4). The model picker groups match these.
- **Providers** (`Services/AIClient.swift:25-150`): omni (Dotmini), anthropic, openai, gemini, deepseek, 9router, openrouter, groq, mistral, kimi, perplexity, perch, tokenme, typhoon, cerebras, together, fireworks, minimax, nvidia, qwen, grok, glm, copilot, aipass, custom, local. Base URLs are **data** (provider registry JSON with per-provider base URL, auth scheme, tool-calling mode, streaming dialect), user-overridable (`byok_base_url_<provider>`).
- **Dialects:** Anthropic Messages (native `tool_use`, prompt caching), Gemini (`functionCall`/`functionResponse`), OpenAI-compatible chat completions (`tools`, `tool_choice:auto`, role `tool`) incl. robust streamed tool-call assembly keyed by call id (`StreamedToolCallAccumulator`), Codex Responses (`function_call_output`), Google Code Assist (`v1internal`). **Text tool bridge** `<tool_call>{"name","arguments"}</tool_call>` only for backends without native tools (and auto-switch when an endpoint answers 400/422 "tools not supported" — remember per endpoint+model in `XMLToolBridgeRegistry`); render tool turns as `<tool_call>`/`<tool_response>` text, never raw JSON (`AIClient.textBridgeTurn`). Parse common text tool-call dialects from content (DeepSeek DSML, Qwen ✿FUNCTION✿, Mistral `[TOOL_CALLS]`, Llama `<|python_tag|>`, fenced json).
- **Model catalog** (`AIModelCatalog.swift`): built-in fallback + live `GET <cloud>/models` + per-provider live lists (OpenAI, Gemini, Anthropic, Ollama `/api/tags`), 15-min TTL, stale-id normalization. Ship the fallback list as a data file updated by remote config.
- **Failover** (`AgentService.swift` `resolveFailoverCandidate`): on 429, 401/402/403/404/422, 502/503/529 or a repeated transient error, switch to the next untried provider/model from an ordered, *configurable* candidate list (subscription pools → Copilot → other connected subscriptions → BYOK); a provider switch does not count as an iteration; setting `AutoFailoverEnabled` (default on). Show the failover alert bar (§1.6) and record it in `harnessTrace.failovers`.
- **Ghost text** (`ACPGhostTextBridge.swift`, `microcode_core::fetchGhostText`): FIM cascade with per-provider latency budgets (Cerebras 380 ms, Groq 420, Copilot 500, Codestral 500, Gemini 550, OpenAI 550, DeepSeek 600, custom 400).

### 3.7 Skills (`Services/AgentCore/SkillRouter.swift`, `Views/Settings/AgentSkillsView.swift`)

- **Format:** folder with `SKILL.md` (YAML front matter `name`, `description`, optional `license`, `metadata`; markdown body) + optional `scripts/`, `reference/`, `examples/`. Built-ins ship in the app (`MicroCode/Resources/BuiltinSkills/`: agent-desktop, frontend-design, mcp-builder, theme-factory, webapp-testing, openthai-ocr, microcode-anti-slop, microcode-arc-lang, microcode-harness-core, microcode-security-baseline, microcode-skill-authoring, microcode-swift-macos-ui → add a `microcode-windows-ui` sibling, microcode-thai-ui-typography).
- **Discovery roots:** `~/.microcode/skills`, `~/.agents/skills`, `~/.claude/skills`, `~/.claude/plugins`, `~/.codex/skills`, `~/.codex/plugins/cache`, `~/.gemini/config/{skills,plugins}`, `~/.gemini/antigravity/builtin/skills`, bundled skills, workspace managed `skills`, `<ws>/.microcode/skills`, `.skills`, `.agents/skills`, `skills` (on Windows `~` = `%USERPROFILE%`; also scan other fixed drives' `\.agents\skills`). Id = slug `name` else folder name; `microcode-` prefix reserved; project skills are opt-in and get a `project-` prefix instead of shadowing built-ins. Disabled lists persisted.
- **Progressive disclosure:** (1) `microcode-harness-core` always injected (≤6,000 chars); (2) catalog `## AGENT SKILLS` + `<available_skills>` "- id: description" (description ≤200 chars, total ≤8,000, stable order builtin < user < ecosystem < plugin-cache then id, overflow summarized "N more installed skills… (family ×n)"); (3) explicit `/skill-id` at message start or `$skill-id` anywhere (max 3) injects the full body (≤16,000) + script list; (4) the model uses `skill_engine` — `match` (BM25 over id×2 + name + description, Thai word segmentation, platform-family gating, relative cut-off 0.4, evidence share 0.6), `read` (exact id → exact name → unique prefix, ≤20,000 chars), `run_script`, `crystallize` (write a new SKILL.md). Routing regression cases: `Scripts/tests/run-skill-routing.sh`.

### 3.8 MCP

**MicroCode as an MCP server** (so Omni AI, Claude Desktop, Claude Code, Cursor… can drive the IDE):
- In-app bridge (`Services/MCPServer.swift`): JSON-RPC `initialize`, `server/discover`, `tools/list`, `tools/call`, `resources/list|read` (`workspace://project`, `workspace://active-file`), `prompts/list`, `ping`; protocol versions 2024-11-05 → 2025-11-25 (+ stateless 2026-07-28) (`MCPProtocolSupport.swift`). Tools: `read_file`, `write_file`, `edit_file`, `search_files`, `list_files`, `run_terminal`, `git_status`, `get_diagnostics`, `microcode_run_playground`, `microcode_run_cell`, `execute_code`, `microcode_open_snippet`, `microcode_sync_account`, `device_runtime`, `microcode_skill_router`, `microcode_swarm_dispatch`, `ide_browser`, `preview_control`, `editor_control`, `lsp_intelligence`, `api_studio`, `database_studio`, `computer_use`, `agent_desktop`, `openthai_ocr`. Transport: loopback HTTP (`/v1/mcp`, `/v1/mcp/sse` → `endpoint`, `/v1/mcp/message?sessionId=`), plus `/v1/run` (open & run a snippet), `/v1/auth/sync` (browser → app session sync), `/v1/status`, `/v1/health`. Auth: per-launch bridge token file in the user profile (ACL'd) required as `Authorization: Bearer` or `X-MicroCode-Bridge-Token`, constant-time compare; loopback `Host` check; origin allow-list (Dotmini domains + localhost, echoed, never `*`); browsers may never call MCP or computer-use.
- Stdio servers for external hosts: `microcode-mcp` (Rust, `backend/src/bin/microcode_mcp.rs`: file_read, file_write, replace_in_file, list_directory_tree, grep_search, shell, playground_run, cell_run/create/list, ardium_run, microcode_run_cell, microcode_run_playground, microcode_get_runtimes) — ship it next to the exe and offer one-click registration in Claude Desktop / Claude Code / Cursor configs.
- **Omni AI:** Omni AI's own MCP server (separate repo) exposes `microcode_run_playground`, `microcode_run_cell`, `microcode_practice_challenge`, `microcode_get_runtimes`, `microcode_diagnose_code` against the Dotmini cloud API (`/api/run-code`, `/api/sandbox/execute`, base from `MICROCODE_API_URL`, auth `MICROCODE_API_KEY`). To let Omni AI *command the running IDE*, Windows must (1) expose the bridge above, (2) handle the deep links `microcode://open|run|playground|…snippet…?code|base64&lang&action` and `POST /v1/run` exactly like `AppState.openSnippetFromOmniAI` (`Models/AppState.swift:3423`), and (3) ship an "Omni AI" entry in the MCP client list (below) so the agent can call Omni AI tools. The Dotmini account/platform key (§4) is the shared identity.

**MCP client** (`Services/ExternalMCPManager.swift`, `Services/MCPAuth.swift`):
- Config `{"mcpServers": {name: {command, args, env} | {url, headers}}}` merged from: workspace `.microcode/mcp.json`, `.mcp.json`, `.cursor/mcp.json`, `.vscode/mcp.json` (Workspace Trust required); managed `~/.microcode/workspaces/<id>/mcp.json`; user `~/.microcode/mcp.json` (primary), `~/.cursor/mcp.json`, Windsurf, Codex, Gemini/Antigravity configs, Claude Desktop config (`%APPDATA%\Claude\claude_desktop_config.json` on Windows), plugin folders.
- Transports: stdio (graceful: close stdin → terminate → kill), Streamable HTTP (`Accept: application/json, text/event-stream`, echo `Mcp-Session-Id`), legacy SSE.
- OAuth: RFC 9728 protected-resource metadata, AS metadata, dynamic client registration, PKCE S256, RFC 8707 `resource`, RFC 9207 `iss`, RFC 8252 loopback redirect, refresh; on 401/403 refresh once then surface `AUTH_REQUIRED`. Tokens live in the credential store bound to the origin, never in mcp.json.
- Tool exposure: at most 12 external tools eagerly per run (router by intent) + explicitly mounted ones; `mcp_orchestrator.synthesize` can generate a small stdio server under `.microcode/mcp/`.

### 3.9 ACP — Agent Client Protocol (`Services/AgentCore/ACPProtocol.swift`, `ACPHostService.swift`, `ACPServerService.swift`)

- **Host external agents:** types claudeCode (`claude`), agy, openCode, codex, geminiCLI (`gemini`), cursorAgent, githubCopilot, goose, cline, qwenCode, aider, zed, custom. Binary discovery on PATH + well-known install dirs (Windows: `%LOCALAPPDATA%\Programs`, `%APPDATA%\npm`, scoop/winget shims). JSON-RPC 2.0 over stdio, `protocolVersion: 1`: `initialize` (clientInfo MicroCode, capabilities `fs.readTextFile`, `fs.writeTextFile`, `terminal`), `session/new` (cwd + MicroCode MCP servers), `session/prompt`, `session/cancel`, `session/resume`, `session/close`; agent→client requests `fs/read_text_file`, `fs/write_text_file`, `session/request_permission`, `terminal/create|output|wait_for_exit|kill|release`, `authenticate`. Agent counts as ACP if args include `acp`, `--acp`, `--acp-server`, `--experimental-acp` or the binary ends with `-acp`; otherwise use the headless CLI fallback (claude `-p … --output-format stream-json --include-partial-messages --verbose [--mcp-config] [--model] [--resume]`, gemini `-p … --output-format stream-json`, codex exec, aider `--no-auto-commits --no-git --yes --message`, …).
- **Permissions:** modes reviewEach / autoApproveReads / fullAuto; others go through the same approval UI (§3.5) with identity `acp.<kind>`; reply with the agent's `optionId` (fallback `allow_once`/`reject_once`) or `cancelled`. "Busy" means a prompt in progress (`isRunningTask`), not merely connected.
- **Sessions:** stored redacted under `acp-sessions/<sessionId>.json` (user-only ACL).
- **MicroCode as an ACP agent** (`--acp-server`): `initialize` (loadSession, prompt capabilities), `authenticate`, `session/new|load|resume|list|close|delete|set_mode|set_model|cancel|prompt`; modes `agent`, `plan` (read-only), `arena` (best-of-N). Streams `agent_message_chunk`, `tool_call`, `tool_call_update`, `session_info_update`.

### 3.10 Sub-agents, swarm, PNS

- `SubAgentSpawnPolicy.swift`: max depth 2, max 8 concurrent; undefined types get read-only + MCP tools. Archetypes: architect, frontend_engineer, backend_engineer, bug_hunter, test_runner, security_auditor, mobile_device_controller, autonomous_loop (`SubAgentHarness.swift:62`); ≤100 model calls each; inbox + shared blackboard; may delegate to an ACP CLI. UI: SubAgent Monitor sheet.
- PNS (`Services/PNS/`): state in `~/.microcode/pns/` (synaptic weights, procedural playbooks, semantic invariants, missions, WAL); routes MCP tools by tract (code/AST, data/cloud, browser/visual, device/hardware, knowledge/science); headless daemon `--pns-daemon`.

---

## 4. Accounts, cloud and subscriptions

### 4.1 Login (Dotmini ID)

- Backend: self-hosted **Supabase GoTrue + PostgREST** (`Services/SupabaseAuthService.swift`). Config keys `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_AUTH_REDIRECT_URL`, bootstrapped from the auth-config endpoint (`<portal>/api/microcode/auth-config` → `{url, anon_key, redirect_url}`) and overridable per §5.1. **Do not embed keys in source**; the anon key comes from config/bootstrap.
- Flows: email+password `POST {base}/auth/v1/token?grant_type=password` (header `apikey`); sign-up `POST /auth/v1/signup` with `data.display_name` (handle "confirm email" → no session); reset `POST /auth/v1/recover`; **Google OAuth with PKCE** — open the portal sign-in page in the system browser, receive `microcode://auth/callback?code&state` (validate scheme/host/path/state, single code, 10-min expiry) → `POST /auth/v1/token?grant_type=pkce` (`auth_code`, `code_verifier`); also accept the browser→app sync `POST /v1/auth/sync` on the loopback bridge from allow-listed origins. Register the `microcode:` URL protocol on Windows (single-instance redirect to the running app).
- Session `{accessToken, refreshToken, expiresAt, userID, email}`; expired = within 60 s of expiry. Refresh: single-flight `POST /auth/v1/token?grant_type=refresh_token` (8 s timeout); 400/401/403 ⇒ re-check a session rotated by the sibling edition, then sign out with a reason ("reauth" banner); network errors keep the still-valid token. Sign-out clears every `supabase.*` credential and cancels payment watches.
- Entitlement: `GET <portal>/api/subscription/status` (Bearer) → plan, role, `ai_quota`, `ai_used`, credit balances in THB, `billing_mode`; merge with PostgREST `users` row; fallback `POST <portal>/api/auth/sync`.
- **Shared identity between editions:** MicroCode and MicroCode AI share the session (on Mac via two settings suites). On Windows store it once in the credential store under the same account names and notify the other edition (named pipe/`WM_COPYDATA`/file watcher) when it rotates.
- Opening the web dashboard passes tokens in the URL **fragment** only, never query or logs.

### 4.2 Dotmini Cloud (gateway + billing + platform key)

- **Gateway:** OpenAI-compatible `/v1` (chat/completions, models, embeddings) at the configured cloud base (`dotminiProxyURL`); auth = platform API key, else the Supabase JWT; empty ⇒ 401 with reauth reason.
- **Platform key** (`Services/DotminiPlatformKeyService.swift`): prefixes `sk-dotmini-live-`, `sk-dotmini-ent-` (enterprise), `mci-live-`; validate `GET /api/v1/platform/me` with header `X-Dotmini-Client: microcode|microcode-ai`; one-click `microcode://platform-connect?code=otc_…` → `POST /api/platform/connect/exchange`; auto-provision `POST /api/platform/keys/create {name, prefix}`; `/platform/me` also returns plans and the shared THB/USD credit pool (Omni AI ⇄ MicroCode unification).
- **Billing** (Beam payment gateway, THB, PromptPay): `POST <portal>/api/payment/beam-checkout {plan, uid, email, fullName, billingInterval, paymentMethod:"promptpay", seats, amountTHB?}` → `{url, orderRef, paymentLinkId|sessionId, amountTHB}`; plans `microai_lite`, `microai_pro`, top-ups `ai_topup_100`, `ai_topup_custom`; `POST /api/payment/verify` → `{verified, isAICreditTopup, status, checkoutUrl}`; poll every 4 s for 3 min then every 10 s up to 15 min, then refresh entitlement. Plan names, prices and credits come from the server, not code.
- Health probe (keep it): models list → bootstrap → optional sign-in → refresh → entitlement → checkout creation → streaming test per model, with redacted output (`DotminiCloudProbe.swift`).

### 4.3 Subscription connections (`Services/SubscriptionAuthManager.swift`, `AIClient.resolveSubscriptionExecutionTarget`)

Providers: omni_ai (AIPass / TH-AI Passport), thai_gemini_enterprise, tokenme, chatgpt, claude, gemini, deepseek, copilot, glm, openrouter, groq, mistral, kimi, perplexity, perch, typhoon, qwen, grok, cerebras, together, fireworks, minimax, nvidia. Multiple accounts per provider with rate-limit rotation. **BYOK and subscription are isolated**: subscription mode never falls into BYOK keys and vice-versa; "No active Web Subscription" is an explicit error.

| Provider | How it connects (same on Windows, Windows paths in parentheses) | Route |
|---|---|---|
| ChatGPT | Codex OAuth: read `~/.codex/auth.json` (`%USERPROFILE%\.codex\auth.json`; skip `auth_mode=apikey`), refresh at the OpenAI OAuth token endpoint with the Codex public client id from config | Codex Responses backend; else `codex` CLI; else AIPass/Copilot |
| Claude Pro/Max | `claude auth status --json` (strip `ANTHROPIC_API_KEY`, 5 s timeout) must report `loggedIn` + a `subscriptionType`; cached 10 min | `claude` CLI as a model backend (text tool bridge); or claude.ai web session (WebView2) |
| Gemini | Gemini CLI creds `~/.gemini/oauth_creds.json` or interactive loopback PKCE OAuth (`127.0.0.1:<random>/oauth2callback`, offline access); refresh at Google token endpoint | Google Code Assist `v1internal` (`loadCodeAssist`/`onboardUser`); else API key; else AIPass |
| Copilot | GitHub device flow (client id from config) or `gh` CLI host token / `COPILOT_TOKEN`; exchange for a Copilot token | Copilot chat API |
| AIPass / Omni AI | session cookie from in-app web login (WebView2 cookie observer) or env/file | AIPass gateway (text tool bridge) |
| Thai Gemini Enterprise | Vertex AI Search / Agentspace session (config id + session from login sheet, stored per user) | text bridge with the 14K budget (§3.3) |
| Others | API-style subscription keys | provider base URL |

Each connection has a health probe ("Reply with exactly: OK") classifying noCredit / authExpired / quota / modelOrEndpoint / providerDown (`SubscriptionHealthProbe.swift`) — surface it in Settings → AI & Agent.

**Local subscription gateway** (`LocalSubscriptionGatewayService.swift`): OpenAI `/v1/chat/completions` + Anthropic `/v1/messages` + `/v1/models` + `/health` served on loopback, backed by the subscription pool, so ACP/CLI agents can use the user's subscriptions. On Windows it **must** require a token and must not send `Access-Control-Allow-Origin: *`.

### 4.4 Enterprise

- Modes: disabled, dotmini_enterprise, gemini_vertex, custom_gateway (`EnterpriseAIAuthService.swift`). Policy source order: machine policy (Windows: Group Policy/registry `HKLM\Software\Policies\Dotmini\MicroCode`, equivalent of the Mac MDM suite) → user settings. Keys: org id, gateway URLs, Vertex project/location/SA, ZDR, local DLP, command firewall, confidential split-routing (after a confidential file such as `.env*`, `*.pem`, `*.key`, `id_rsa*`, `secrets/` is read, route the rest of the turn to the local LLM), air-gapped lockdown. Workspace `.microcode/enterprise-policy.json` may only tighten. Headers `X-Dotmini-Client`, `X-Dotmini-Enterprise`, `X-Dotmini-ZDR`, `X-Dotmini-Org-ID`. Audit every enforcement (Flight Recorder).
- Connection profiles (`EnterpriseConnectionProfiles.swift`): dialects OpenAI gateway, Azure OpenAI, Vertex, Agentspace, Bedrock, Anthropic gateway, Dotmini enterprise; auth bearer, api-key headers, `Ocp-Apim-Subscription-Key`, gcloud ADC, service-account JSON, Azure Entra (`az account get-access-token`), Bedrock key / SigV4; smart paste of env/cURL/URL (incl. `HTTPS_PROXY`); team share `microcode://enterprise?config=<b64>` with secrets stripped.

---

## 5. Connectivity features

### 5.1 Configuration layer (no hard-coding)

One typed config object, loaded at start and hot-reloaded, with precedence **signed remote config → environment → user settings → bundled `defaults.json`**. At minimum it holds: portal base, auth-config URL, Supabase URL/anon key/redirect, cloud gateway base, platform API origins, billing endpoints, relay hosts, Cloud GPU base, telemetry endpoint, update feed, provider registry (base URLs, dialects), model fallback list, failover candidate order, OAuth client ids (public ids only), local server ports (0 = random), feature flags, plan/price display data. Secrets are never in this object.

### 5.2 Credentials and storage

- Credential store accounts (keep these names): `supabase.session.v1`, `supabase.entitlement.v1`, `dotmini.platform.api-key.v1`, `sub.<provider>` (subscription tokens), `byok.<PROVIDER>_API_KEY`, `dotmini.enterprise.*`, `dotmini.enterprise.profile.<id>.*`, `cloud-gpu.managed-session.v1`, `cloud_gpu_{runpod,vast,lambda}_api_key`, `ssh_pwd_<uuid>`, `ssh_otp_<uuid>`, `phone-companion.token`, `mcp.oauth.<origin>`. Use Windows Credential Manager/DPAPI (CurrentUser); never settings files, never env files, never logs.
- Tokens never in URLs (except one-time pairing codes), never in process arguments (pass via stdin/env/pipe), never in crash reports.

### 5.3 Local LLM pool and gateway

- Discovery (`LocalLLMService.swift`): Ollama 11434/11435, LM Studio 1234–1236, llama.cpp 8080–8082, LocalAI 8080/8081 (MLX is Mac-only; add DirectML/CUDA builds of llama.cpp on Windows), LAN subnet scan, DNS-SD `_microcode-llm._tcp` and `_ollama._tcp`. Pool routing `auto-pool`/`local-pool` = least in-flight server that has the model; `<endpoint>||<model>` explicit form. Hugging Face GGUF hub.
- **LLM gateway** (`LocalLLMGatewayService.swift`): re-export the local LLM as OpenAI `/v1` (SSE) on the LAN for phones/other PCs, QR + deep link `microcode://llm-connect?endpoint&token&name`, token required (constant-time), optional worldwide access through a tunnel (cloudflared). Store its token in the credential store.

### 5.4 Mobile Connect 2.0 (phone companion) (`PhoneCompanionService*.swift`, UI Settings → Connect with Phone)

- Zero-install mobile web app + PWA served by the desktop (no native phone app). Transports: **LAN** (listener + DNS-SD `_microcode-phone._tcp`), **Tailscale** (MagicDNS / 100.64/10 address), **Online relay** (WebSocket uplink to the Dotmini relay; node proof from a per-install secret, relay epoch, user hint hash, Supabase bearer; public URL `https://<relay-host><poly_prefix>`; keepalive 3.5 s; auto-reconnect).
- Pairing: one-time QR code (`?pair=<code>`, rotated on use), or **6-digit PIN** (`POST /api/pair/verify-pin`, 6 failures/IP → 5-min lock, rotates on success); long-lived device token (32 random bytes, rotate every 30 days or on demand); new devices require approval on the desktop.
- Auth: `X-Companion-Token` / bearer / HttpOnly SameSite cookie `mc_token` (Secure behind HTTPS); **all state-changing POSTs require the custom header** (CSRF). Local-desktop detection must not trust forwarded headers from the relay.
- Phone features: live state + SSE stream, chat with the agent, stop, approve/reject plans and tools, model select, workspace/session switch, new session, file search/read, git status/diff/stage/revert/AI commit-push, terminal scripts/exec, preview ports with an authenticated reverse proxy `/preview/<port>/*`, device list, **build & run on device** (`POST /api/run`, `/api/run/status`), camera/screenshot attachments, OpenAI-compatible `/v1/*` via the LLM gateway. Notifications via ntfy / Telegram bot / webhook (user-configured). Keep the PC awake while a phone session is active (`SetThreadExecutionState`).

### 5.5 Realtime collaboration (`CollaborationService.swift`, `CollabTextOperation.swift`)

Host listener (port range from config) + DNS-SD `_microcode-collab._tcp`; join by invite link, `<host>:<port>#CODE`, relay URL or 6-char room code; HTTP `/api/collab/{join,workspace-bundle,sync,file,op,ops,edit,fs-event,chat,task,leave}` + WebSocket `/ws/collab?code=`; follow mode; **AI teammate** participant ("MicroCode AI") broadcasting cursor/status while the agent works; online relay like §5.4. Every route (including bundle/file/sync) must check the room credential (query `code`, header `X-Collab-Code` or cookie `mc_collab_code`); room codes from a CSPRNG. A Windows host and a macOS host must be interchangeable: either can host, either can join, and both see the same files change keystroke by keystroke.

**Invite links open the app, not a web page.** The share link is `<base>/join?code=CODE` (`base` = LAN `http://ip:port`, tunnel URL, or relay URL with its path prefix). `/join` serves a small page that immediately navigates to `microcode://collab?token=<url-encoded base + "/?code=" + CODE>` and shows "Open in MicroCode" plus an install link. `/` serves the same page unless the host ticked "Also allow editing in a web browser" (then `/?code=` is the browser editor). Windows must register the `microcode:` protocol (single instance — forward the URL to the running window), parse `token` exactly like `joinSession` (accept `http(s)://…/?code=`, `…/join?code=`, `host:port#CODE`, bare code), and **always confirm** before joining or hosting from a link (any web page can open `microcode://`): "Join live session CODE? Host: …" / "Share <workspace>?". Joining while in another session leaves it first.

**Co-editing protocol `ot1`** — operational transformation, wire-compatible with ot.js `TextOperation`. Implement it once in C# from `CollabTextOperation.swift`, which is the reference (apply, compose, transform, fromDiff, transformIndex, client state machine, host log) and is covered by `Scripts/tests/run-collab-ot.sh`; the web portal carries the same algorithm in JavaScript (`run-collab-ot-web.sh`). Port both fuzz tests and run them in CI.

- *Operation:* JSON array; positive int = retain n, negative int = delete n, string = insert. All offsets are **UTF-16 code units** (C# `string` indices match). Canonical form: merge neighbours, insert before delete. `fromDiff` = common prefix/suffix single splice, never splitting a surrogate pair.
- *Transform tie-break:* `transform(clientOp, hostOp)` — on equal insert offsets the first argument goes first. Host and every client use this argument order.
- *Handshake:* client `hello {userId, displayName, color, role, caps:["ot1"]}` → host `assignedIdentity {color, caps:["ot1"]}`. `join`/`sync` JSON also carries `caps`. Without `ot1` on both sides fall back to legacy full-text `edit`/`fileBuffer` (old builds only).
- *Client → host:* `op {path, baseRevision, op, opId, userId, displayName, color}` — one op in flight per file; later local edits are composed into a buffer and sent after the ack (ot.js `Client`). `opId` is unique per op and reused when resending after a reconnect (the host deduplicates).
- *Host → everyone (author included — that is the ack):* `op {path, revision, op, authorId, authorName, authorColor, opId?, length?}`. Revisions increase by exactly 1 per commit. The host transforms late ops against every commit after `baseRevision` (keeps ≥1000 per file), applies, writes the file, updates its own editor in place, and broadcasts.
- *Client on `op`:* `revision <= mine` → ignore; `revision != mine + 1` → resync; `opId == outstanding` → ack (send buffer); else transform outstanding and buffer against it, apply the result to the editor **mapping every caret/selection with `transformIndex`** (text inserted at a caret stays after it) and keeping the scroll anchored. If nothing is pending and `length` ≠ local length → resync.
- *Errors / resync:* host replies `opError {path, reason: stale|invalid|too_large, revision, content, resync:true}`; the client replaces its state with that snapshot and replays commits that arrived meanwhile. `opSync {path, since}` asks for missed commits (sent as `op` messages) — send it for every tracked file after (re)connecting, then resend the outstanding op.
- *Without WebSocket (relay):* `POST /api/collab/op` (same body) replies `{ok, commits:[…every commit after baseRevision, including yours]}`; poll `GET /api/collab/ops?path=&since=` (~700 ms) for files you track. Process commits with the same rules as above.
- *Editor bridge (the part that made lines jump before):* before applying a remote op, flush keystrokes the editor has not reported yet (debounce) as a local op; apply remote ops to the text buffer directly, never by re-assigning the whole document; cancel any pending debounced "text changed" push captured before the remote op, or it will revert it.
- *Files:* creating a new file or folder = `fsEvent`/`POST fs-event {op: write|mkdir|rename|delete, path, newPath?, content?}`; the host relays `fsEvent` with the new file's `revision`. Saving or rewriting a file that already exists is just an edit — send it as `op`, never as a full-content `write`. Paths are workspace-relative with `/`, sanitized (`..` removed) and must stay inside the shared root.

### 5.6 Cloud GPU (Settings → Cloud GPU; Notebook kernels)

- **Managed Dotmini Cloud GPU** (`Kernel/CloudGPUService.swift`): `GET /catalog`, `GET /wallet` (satang), `POST /sessions {gpuId}` → `{sessionId, wssURL, jupyterToken}` (409 = insufficient funds), `GET/DELETE /sessions/{id}`, `POST /wallet/topup {packageId|amountBaht}` → checkout URL; auth Supabase JWT or `mci-live-` key; Jupyter `/api/contents` for files with `Authorization: token …`; per-session budget cap (฿100–1,000) and idle auto-stop (15–120 min). UI tabs GPU Cluster / GPU Wallet / Git Ingest / SSH-Custom.
- **BYO cloud:** RunPod (GraphQL), Vast.ai, Lambda (`Kernel/RemoteProviderService.swift`) — list/start/stop/terminate, upload the managed SSH public key, then `Kernel/RemoteGPUService.swift` starts a remote Jupyter with a generated token and SSH-forwards it. Google Colab bridge via a bootstrap cell that returns `microcode://colab?endpoint&token`. Unified compute picker: Local / Colab / RunPod / SSH / Lambda / Vast (`ElasticComputeFabric.swift`). Git tokens are passed with a credential helper, never embedded in clone URLs.

### 5.7 SSH mode (Remote Explorer)

Server model: host, port, user, auth (password/key), key path, OTP, type (SSH/SFTP/FTP/FTPS), provider, ProxyJump, agent forwarding (`Views/RemoteXView.swift:15-235`); import from `~/.ssh/config` (`SSHConfigParser.swift`). Connect through the backend `/api/remote/*` + WS shell, falling back to the system OpenSSH client (`C:\Windows\System32\OpenSSH\ssh.exe`) with connection sharing where supported. Terminal tab = PTY (ConPTY). Remote files are mirrored to a local cache and re-uploaded on save (`RemoteWorkspaceManager.swift`). Host keys: first-use prompt showing the fingerprint (not silent accept-new); passwords via an askpass helper reading memory, never temp files.

### 5.8 Other studios

Database Studio (SQLite/Postgres/MySQL connections, query editor, Ctrl+Enter), API Studio, CI/CD, Container Studio (Docker Desktop on Windows), Embedded Studio (serial via Win32 COM ports, esptool/avrdude/arduino-cli), Science (AlphaFold, MedGemma), Runtime Manager (portable Python/Node/Go/Rust/Java runtimes under the app data dir + Arc 3 toolchain with auto-update from `ArcToolchainUpdater.swift`).

---

## 6. Production requirements checklist

- [ ] Every endpoint/port/id from §5.1 config; zero literals (CI grep gate for `https://`, `http://`, `:\d{4}` in UI/services).
- [ ] All local servers: loopback unless the feature is explicitly LAN; per-launch or per-device token; constant-time compare; origin allow-list; no wildcard CORS; CSRF header on state changes; rate limits on pairing.
- [ ] Credentials only in Credential Manager/DPAPI; secrets never in argv, URLs, logs, crash dumps, telemetry.
- [ ] Signed MSIX/installer, auto-update channel, crash reporter with symbol upload, structured redacted logs, opt-in telemetry.
- [ ] Every network call: timeout, retry with jittered backoff where idempotent, cancellation, user-visible error with a retry action.
- [ ] Accessibility: keyboard navigation for every control, UI Automation names (also needed for computer-use QA), high-contrast theme.
- [ ] Localization: English + Thai strings in resource files (existing Thai copy kept verbatim).
- [ ] Parity tests: the agent eval in `Scripts/eval/` (same cases, same grader) must pass on Windows at least as well as on Mac; regression suites in `Scripts/tests/` ported for the shared logic (follow-up intent, text bridge, skill routing, task file, turn trace, streamed tool calls).

## 7. Suggested build order

1. Rust core + backend + MCP binary building on Windows; config layer; credential store; logging/crash/update.
2. Shell: window, header, sidebars, splitters, themes, settings frame, keymap (§1.1–1.3, 1.8–1.9).
3. Agent panel + agent runtime + tools + approval + providers (BYOK first, then Dotmini Cloud) (§1.6, §3).
4. Login + entitlement + billing + platform key (§4.1–4.2); subscriptions (§4.3).
5. Code editor, terminal, Git, Problems (§1.4); Playground, Notebook/Cells (§1.5).
6. MCP server/client, ACP host/server, skills, sub-agents (§3.7–3.10).
7. SSH mode, Cloud GPU, Local LLM pool/gateway, Mobile Connect, Collaboration (§5).
8. Remaining studios, enterprise, MicroCode AI edition packaging; parity eval and release.

## 8. Source index (macOS reference)

> Files from the 2026-11-21 agent-quality work — `FollowUpIntent.swift`, `AgentTaskFile.swift`, `AgentTurnTrace.swift`, `AgentEvalGrader.swift`, `AgentEvalRunner.swift`, `TextBridgeContextBudget`/`TextBridgeTranscript` in `AIStreamPrimitives.swift`, `AIClient.textBridgeTurn`, `Scripts/eval/` — land on `main` with that change; until then treat their descriptions here as the spec.

| Area | Files |
|---|---|
| App/shell | `MicroCode/MicroCodeApp.swift`, `Views/ContentView.swift`, `Views/Workspace/*`, `Models/AppState.swift` |
| Agent UI | `Views/AI/AIAgentView.swift`, `AIAgentChatStageAndCells.swift`, `AIAgentMessageRowsAndDiffCards.swift`, `AIAgentTimelineAndMenus.swift`, `AIAgentMarkdownAndCodeViews.swift`, `ToolApprovalView.swift`, `SlashCommandSuggestionView.swift` |
| Agent runtime | `Services/AgentService.swift`, `AgentTranscriptStore.swift`, `AgentMemoryService.swift`, `ProjectMemoryService.swift`, `Services/AgentCore/*` (AgentToolBox, ToolScope, SkillRouter, FollowUpIntent, AgentTaskFile, AgentTurnTrace, PlanModePolicy, FileFreshnessGuard, AgentPrivacyGuard, MultiPlatformRulesEngine, ACP*, AgentEval*) |
| Providers | `Services/AIClient.swift`, `AIStreamPrimitives.swift`, `AIModelCatalog.swift`, `LocalLLMService.swift` |
| MCP | `Services/MCPServer.swift`, `MCPProtocolSupport.swift`, `ExternalMCPManager.swift`, `MCPAuth.swift`, `mcp-server.py`, `backend/src/bin/microcode_mcp.rs` |
| Accounts/cloud | `Services/SupabaseAuthService.swift`, `AuthService.swift`, `DotminiPlatformKeyService.swift`, `BillingService.swift`, `SubscriptionAuthManager.swift`, `SubscriptionHealthProbe.swift`, `LocalSubscriptionGatewayService.swift`, `EnterpriseAIAuthService.swift`, `EnterpriseConnectionProfiles.swift` |
| Connectivity | `PhoneCompanionService*.swift`, `CollaborationService.swift`, `LocalLLMGatewayService.swift`, `Kernel/CloudGPUService.swift`, `Kernel/RemoteProviderService.swift`, `Kernel/RemoteGPUService.swift`, `Views/RemoteXView.swift`, `RemoteWorkspaceManager.swift` |
| Rust | `backend/src/main.rs`, `backend/src/agent_kernel.rs`, `backend/src/local_auth.rs`, `microcode_core/` |
| Eval & tests | `Scripts/eval/`, `Scripts/tests/` |
