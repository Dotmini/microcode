# MicroCode macOS — screen captures (reference for the Windows port)

Captured 2026-11-21 from the installed build **MicroCode 2.5.43 (build 40)** on macOS, Retina, scaled to 2400 px wide, 256-colour PNG.
All captures use a neutral demo workspace (`MicroCodeDemo`: `src/main.py`, `src/fib.swift`, `web/index.html`, `notebooks/`) so no real project content is shown.

**Redactions** (pixelated + blurred): account e-mail and display name, Git user name/e-mail, phone-pairing QR code and PIN, SSH host names / user names / IP addresses, local file-system paths (`/Users/…`, `/var/folders/…`, scratch paths), shell prompt (user@host), MCP server commands/paths, Google account avatar, and a private Science-mode chat transcript.

| File | Screen | How to open | What it shows |
|---|---|---|---|
| [01-editor-mode.png](01-editor-mode.png) | Code Editor mode | Toolbar **Code Editor** (⌃1) | File tree, tabs, breadcrumbs, syntax-highlighted Python, console dock |
| [02-more-mode-menu.png](02-more-mode-menu.png) | More Mode menu | Toolbar **More Mode ▾** | Playground, Cell Mode, SSH Remote Browser, Science, IDE Web Browser, Embed & IoT, API Studio, Extension Studio |
| [03-overflow-menu.png](03-overflow-menu.png) | Toolbar overflow menu | Toolbar **⋯** | Run/Build/Console, specialized studios (Database, API, Apple Container, CI/CD, Collaboration), window & panel toggles, Connect with Phone |
| [04-preview-menu.png](04-preview-menu.png) | Live Preview popover | Toolbar **Preview ▾** | Localhost dock / full browser, iPhone & Android USB, Apple simulators, Android emulator, run-target picker |
| [05-console-output.png](05-console-output.png) | Console — Output | Toolbar **Console** | Output / Terminal / Problems / Analysis tabs, empty output state |
| [06-console-terminal.png](06-console-terminal.png) | Console — Terminal | Console ▸ **TERMINAL** | Embedded zsh session tab bar, "Fix with AI" error banner |
| [07-console-analysis.png](07-console-analysis.png) | Console — Analysis | Console ▸ **ANALYSIS** | Overview / Details / Paper Report, "Ready to analyze" empty state |
| [08-sidebar-git.png](08-sidebar-git.png) | Sidebar — Source Control | Sidebar branch icon | Branch picker, Changes/Branches/History/Stash/CI/CD tabs, clean-tree empty state, commit bar |
| [09-sidebar-search.png](09-sidebar-search.png) | Sidebar — Find in Workspace | Sidebar magnifier (⇧⌘F) | Search field with case / regex toggles |
| [10-sidebar-problems.png](10-sidebar-problems.png) | Sidebar — Issues & Diagnostics | Sidebar warning icon | "No build or analysis errors" empty state |
| [11-git-settings.png](11-git-settings.png) | Git Settings sheet | Menu **Git ▸ Git Settings…** | Config / Repository / Auth / Branches / Preferences tabs, user identity, default branch |
| [12-agent-chat.png](12-agent-chat.png) | AI Agent workspace — Chat | Toolbar **Agent** (⌃2) | Conversations sidebar (workspaces, chats, files), Project Briefing card, composer |
| [13-composer-model-picker.png](13-composer-model-picker.png) | Composer — model/provider picker | Composer provider button | Enterprise API, Subscription, BYOK routers, Local LLM pool, ACP harnesses, Dotmini Cloud; Vertex AI submenu |
| [14-composer-plus-menu.png](14-composer-plus-menu.png) | Composer — "+" menu | Composer **+** | Attach files, mention file, /plan, /review, connect external agents, rules/MCP settings |
| [15-composer-autonomy-menu.png](15-composer-autonomy-menu.png) | Composer — tool autonomy | Composer **Auto ▾** | Safe / Smart / Full Auto |
| [16-composer-agent-mode-menu.png](16-composer-agent-mode-menu.png) | Composer — agent mode | Composer **Agent ▾** | Main Agent, multi-agent teams, specialized subagents |
| [17-composer-run-target-menu.png](17-composer-run-target-menu.png) | Composer — run target | Composer **Local ▾** | Local Mac vs remote servers / cloud, Add Remote Server |
| [18-agent-plan.png](18-agent-plan.png) | Agent — Plan | Agent toolbar **Plan** | Suggestions, "No Implementation Plan Active" panel, Load task.md / Draft Plan |
| [19-agent-task.png](19-agent-task.png) | Agent — Task | Agent toolbar **Task** | Checklist / Spec / Walkthrough / Logs, 12-step autonomous task checklist |
| [20-agent-more-menu.png](20-agent-more-menu.png) | Agent — More menu | Agent toolbar **More ▾** | Walkthrough summary, notebook cells, background worktree agents, token & cost, diagnostic/audit logs, consensus engine |
| [21-agent-team-menu.png](21-agent-team-menu.png) | Agent — Team menu | Agent toolbar **Team** | Team Tasks, Configure Team Collaboration |
| [22-agent-actions-menu.png](22-agent-actions-menu.png) | Agent — Actions menu | Agent toolbar **Actions ▾** | Connect external agents, rules/MCP, switch active agent (Claude Code, AGY, OpenCode, Aider, Codex, Gemini CLI), index, .ARX capsules, undo/clear |
| [23-acp-agent-connections.png](23-acp-agent-connections.png) | ACP — Agent connections | Actions ▸ **Connect External Agents (1-Click)** | Enterprise gateway, built-in subscription gateway, Claude Code / AGY / Codex / Gemini CLI / OpenCode cards |
| [24-acp-ecosystem-rules.png](24-acp-ecosystem-rules.png) | ACP — Agent & Ecosystem Settings: Platform Rules | Agent connections ▸ **Rules, MCP & Advanced Paths…** | Rule discovery (agent.md, AGENTS.md, CLAUDE.md…), add-rule field |
| [25-acp-external-agents.png](25-acp-external-agents.png) | ACP — External Agents tab | Ecosystem Settings ▸ **External Agents** | Detected CLI agents with Connect/Configure, 1-Click install wizard |
| [26-acp-mcp-servers.png](26-acp-mcp-servers.png) | ACP — MCP Servers tab | Ecosystem Settings ▸ **MCP Servers** | Discovered MCP server list layout (entries redacted) |
| [27-notebook-cell-mode.png](27-notebook-cell-mode.png) | Cell Mode (Notebook) | Modes ▸ **Cell Mode** (⌃3) | Cell sheets list, cell toolbar (language, run, DAG, vars, app), code cell, Notebook Agent panel |
| [28-playground-mode.png](28-playground-mode.png) | Playground Mode | Modes ▸ **Playground** (⌃4) | Language/runtime pickers, editor/cell toggle, output pane, auto-run & hot reload |
| [29-science-mode.png](29-science-mode.png) | Science Mode | Modes ▸ **Science** (⌃5) | Research workspace tabs (Project/Structure/Results/Paper), project stats, scientific workflows (chat redacted) |
| [30-ide-web-browser.png](30-ide-web-browser.png) | IDE Web Browser | Modes ▸ **IDE Web Browser** (⌃6) | Embedded browser tabs, address bar, devtools buttons |
| [31-remote-explorer-ssh.png](31-remote-explorer-ssh.png) | Remote Explorer (SSH) | Modes ▸ **Remote Explorer** (⌃7) | Saved servers list, server detail cards, Connect Terminal / Browse Files (SFTP) (hosts redacted) |
| [32-embed-iot-studio.png](32-embed-iot-studio.png) | Embed & IoT Studio | Modes ▸ **Embed & IoT Studio** (⌃8) | Target board, USB serial, sketch editor, flash log, hardware tools list |
| [33-api-studio.png](33-api-studio.png) | API Studio | Modes ▸ **API Studio** | Request builder (method, URL, body/headers/params/auth), response pane, history |
| [34-extension-studio.png](34-extension-studio.png) | Extension Studio | Modes ▸ **Extension Studio** | Open VSX marketplace browser, installed list, extension detail |
| [35-database-studio.png](35-database-studio.png) | Database Studio | ⋯ ▸ **Database Studio** | Connections sidebar, new connection form, empty state |
| [36-apple-container-studio.png](36-apple-container-studio.png) | Apple Container Studio | ⋯ ▸ **Apple Container Studio** | Containers/Images/Deploy/Terminal tabs, daemon warning, empty state |
| [37-cicd-pipelines.png](37-cicd-pipelines.png) | CI/CD Pipelines | ⋯ ▸ **CI/CD Pipelines** | Local Pipelines / GitHub Actions, pipeline list, console, empty states |
| [38-realtime-collaboration.png](38-realtime-collaboration.png) | Realtime Collaboration | ⋯ ▸ **Realtime Collaboration** | Identity, host session (LAN/P2P, HTTPS), join session, Bonjour discovery |
| [39-context-inspector.png](39-context-inspector.png) | Context Inspector | ⋯ ▸ **Show Context Inspector** (⌘I) | Right panel: current file, changed/open files, agent activity |
| [40-runtime-manager-arc.png](40-runtime-manager-arc.png) | Runtime Manager — top | Menu **Tools ▸ Runtime Manager** | New **Arc** toolchain card (version, source, auto-update, Check Now), Python, Node.js |
| [41-runtime-manager-list.png](41-runtime-manager-list.png) | Runtime Manager — scrolled | Same, scrolled | Python, Node.js, Bun, Deno (install), install dir |
| [42-settings-general.png](42-settings-general.png) | Settings — General | MicroCode ▸ **Settings…** (or sidebar Settings) ▸ General | Agent automation, appearance, theme extensions |
| [43-settings-editor.png](43-settings-editor.png) | Settings — Editor | Settings ▸ Editor | Font family/size/weight per surface |
| [44-settings-ai-agent.png](44-settings-ai-agent.png) | Settings — AI & Agent | Settings ▸ AI & Agent | Provider modes, web subscription sessions, active model |
| [45-settings-connect-phone.png](45-settings-connect-phone.png) | Settings — Connect with Phone | Sidebar **Phone** or Settings ▸ Connect with Phone | Mobile Connect 2.0, network mode, QR pairing + PIN (redacted), session token, lock-screen push, active clients |
| [46-settings-team-collaboration.png](46-settings-team-collaboration.png) | Settings — Team Collaboration | Settings ▸ Team Collaboration | Same collaboration panel inside Settings |
| [47-settings-cloud-gpu.png](47-settings-cloud-gpu.png) | Settings — Cloud GPU | Settings ▸ Cloud GPU | GPU hub, instance list with rates, cost guardrails |
| [48-settings-skills.png](48-settings-skills.png) | Settings — Skills | Settings ▸ Skills | Agent Skills Engine (241 skills), search, category filters, skill cards |
| [49-settings-skills-arc.png](49-settings-skills-arc.png) | Settings — Skills (filtered) | Skills search "microcode-arc" | New built-in skill **microcode-arc-lang** |
| [50-settings-mcp-servers.png](50-settings-mcp-servers.png) | Settings — MCP Servers | Settings ▸ MCP Servers | Built-in MCP protocol server status, tools, recent activity |
| [51-settings-tools.png](51-settings-tools.png) | Settings — Tools | Settings ▸ Tools | Code execution, Git, refactoring toggles |
| [52-settings-extensions.png](52-settings-extensions.png) | Settings — Extensions | Settings ▸ Extensions | Extension hub, installed / Open VSX tabs |
| [53-settings-account.png](53-settings-account.png) | Settings — Account & License | Settings ▸ Account & License | Dotmini ID sign-in, cloud credit plans, top-up wallet |
| [54-settings-about.png](54-settings-about.png) | Settings — About | Settings ▸ About | App icon, version 2.5.43 (40), links |
| [55-welcome-projects.png](55-welcome-projects.png) | Welcome Dashboard — Projects | Modes ▸ **Welcome Dashboard** / Help ▸ Welcome | Quick actions grid, recent workspaces (redacted) |
| [56-welcome-templates.png](56-welcome-templates.png) | Welcome — Templates | Welcome ▸ Templates | Project template gallery |
| [57-welcome-ai-architect.png](57-welcome-ai-architect.png) | Welcome — AI Architect | Welcome ▸ AI Architect | Agent chat embedded in the welcome shell |
| [58-first-launch-onboarding.png](58-first-launch-onboarding.png) | First-launch onboarding | Help ▸ **First-Launch Onboarding…** | Welcome sheet, optional Google / Dotmini ID sign-in |
| [59-keyboard-shortcuts.png](59-keyboard-shortcuts.png) | Keyboard Shortcuts | Help ▸ **Keyboard Shortcuts…** | Searchable shortcut list by category (49 shortcuts) |
| [60-git-branches.png](60-git-branches.png) | Source Control — Branches | Sidebar Git ▸ **Branches** | Branch list (empty: demo repo has no commits) |
| [61-git-history.png](61-git-history.png) | Source Control — History | Sidebar Git ▸ **History** | Commit history (empty) |
| [62-git-stash.png](62-git-stash.png) | Source Control — Stash | Sidebar Git ▸ **Stash** | Stash message field + button, "No stashes" |
| [63-git-cicd.png](63-git-cicd.png) | Source Control — CI/CD | Sidebar Git ▸ **CI/CD** | GitHub Actions runs, "No CI/CD runs" |
| [64-editor-html-file.png](64-editor-html-file.png) | Editor — HTML file | Open `web/index.html` | HTML syntax highlighting, language badge |
| [65-device-dock-webapp-preview.png](65-device-dock-webapp-preview.png) | Device Preview Dock — WebApp | View ▸ **Toggle Device Preview Dock** | Right dock: WebApp Preview / iOS Sim / Android Emu tabs, URL bar, responsive picker, build prompt |
| [66-device-dock-ios-simulator.png](66-device-dock-ios-simulator.png) | Device Preview Dock — iOS Sim | Dock ▸ **iOS Sim** | Apple Simulator Preview placeholder, device picker, Start Simulator / Web Preview, hot-reload tooltip |
| [67-device-dock-simulator-menu.png](67-device-dock-simulator-menu.png) | Device Preview Dock — device menu | Dock ▸ **iPhone Sim ▾** | Choose Device & Run…, Refresh Simulators |
| [68-composer-acp-harness-menu.png](68-composer-acp-harness-menu.png) | Composer — ACP Harnesses submenu | Composer provider ▸ **ACP Harnesses ▸** | Harness list (AGY, Claude Code, Codex, Gemini CLI, OpenCode, Cursor, Copilot, Goose, Cline, Qwen Code, Aider) and the AGY model list |
| [69-notebook-vars-inspector.png](69-notebook-vars-inspector.png) | Notebook — Live Kernel Memory | Notebook toolbar **Vars** | Variable / memory inspector strip (empty: 0 vars) |
| [70-notebook-app-mode.png](70-notebook-app-mode.png) | Notebook — App / dashboard mode | Notebook toolbar **App** | Presentation mode: cell outputs only (tables, logs, error output; paths redacted) |
| [71-science-structure.png](71-science-structure.png) | Science — Structure | Science ▸ **Structure** | Protein Structure Preview (PDB / mmCIF / AlphaFold), Choose Structure (chat column redacted) |
| [72-science-results.png](72-science-results.png) | Science — Results | Science ▸ **Results** | Results preview empty state (chat column redacted) |
| [73-science-paper.png](73-science-paper.png) | Science — Paper | Science ▸ **Paper** | Scientific paper workspace, Draft LaTeX Paper (chat column redacted) |

## Zoomed detail crops

Cut from the redacted captures above (2× upscale where small), for pixel-level reference of dense areas.

| File | Source | What it shows |
|---|---|---|
| [d01-editor-toolbar.png](d01-editor-toolbar.png) | 01 | Editor title bar, sidebar icons, tabs, breadcrumbs |
| [d02-agent-toolbar.png](d02-agent-toolbar.png) | 12 | Agent toolbar: Chat / Plan / Task / More / Preview / Team / Actions / mode switcher |
| [d03-agent-composer.png](d03-agent-composer.png) | 12 | Project Briefing card and composer controls |
| [d04-runtime-arc-card.png](d04-runtime-arc-card.png) | 40 | Arc toolchain card (paths redacted) |
| [d05-overflow-menu.png](d05-overflow-menu.png) | 03 | Toolbar ⋯ menu |
| [d06-model-picker-menu.png](d06-model-picker-menu.png) | 13 | Provider picker with submenu |
| [d07-agent-mode-menu.png](d07-agent-mode-menu.png) | 16 | Agent mode / multi-agent team menu |
| [d08-actions-menu.png](d08-actions-menu.png) | 22 | Actions menu |
| [d09-notebook-toolbar.png](d09-notebook-toolbar.png) | 27 | Notebook header, cell toolbar, agent header |
| [d10-skills-cards.png](d10-skills-cards.png) | 48 | Skills search, filters, skill cards |
| [d11-embed-studio-sidebar.png](d11-embed-studio-sidebar.png) | 32 | Embed & IoT Studio tool sidebar |
| [d12-preview-popover.png](d12-preview-popover.png) | 04 | Live Preview popover |

**Not captured:**
- A dedicated ACP chat screen: `MicroCode/Views/AI/ACPAgentChatView.swift` exists, but no current UI presents it. ACP agents are reached through screens 22–26 and the composer picker (13).
- The "Toggle Git Panel" menu item showed nothing beyond the sidebar Source Control view (08, 60–63).
- A running simulator, a physical device or the Android emulator. None was started.
- Cloud GPU Wallet / Git Ingest / SSH tabs: only the default GPU Cluster tab is shown (47).
- Notebook **DAG** is a reactive-mode setting toggle, not a panel; it was switched back off and not captured.
