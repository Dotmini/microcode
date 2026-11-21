# MicroCode for Windows (Native)

MicroCode เวอร์ชัน Windows แบบ native ล้วน: **WPF บน .NET Framework 4.8 (C#)** วาดหน้าจอด้วย DirectX ของ Windows ไม่มี Electron / WebView
หน้าตาและพฤติกรรมพอร์ตตรงจากซอร์ส SwiftUI ใน `../../MicroCode/` (ขนาด, สี, ระยะ, ข้อความ อ่านจากโค้ดจริง ไม่ได้กะจากภาพ)

## Build & Run

ไม่ต้องติดตั้ง SDK, NuGet หรือสิทธิ์ admin — ใช้ตัวคอมไพล์ C# ที่มากับ Windows 10/11

```bat
build.cmd
out\MicroCode.exe
out\MicroCode.exe C:\path\to\project        :: เปิดโฟลเดอร์
```

ผลลัพธ์คือ `out\MicroCode.exe` ไฟล์เดียว (~900 KB) + `MicroCode.ico` รันได้ทันทีบน Windows 10/11 ทุกเครื่อง (.NET Framework 4.8 มีในตัวระบบ)

### ตรวจหน้าจออัตโนมัติ (ไม่ต้องเปิดหน้าต่าง)

```bat
out\MicroCode.exe --snapshot code.png --size 1440x900 --folder C:\repo --file C:\repo\main.swift
out\MicroCode.exe --snapshot agent.png --mode agent
out\MicroCode.exe --snapshot run.png --file hello.py --run      :: กด Run จริงแล้วถ่ายภาพ Console
out\MicroCode.exe --snapshot nb.png --mode notebook --notebook-demo --run-cells --wait 6   :: รันเซลล์ผ่าน kernel จริง
out\MicroCode.exe --snapshot nb2.png --mode notebook --notebook-file demo.ipynb --run-cells --nb-vars --nb-scroll 3 --wait 20
    :: เปิด .ipynb / .mic / .mcnb / .py ในหน่วยความจำ (ไม่บันทึก), --nb-vars แถบตัวแปร, --nb-app โหมด App, --nb-agent แผง Agent, --nb-scroll N เลื่อนไป cell N
out\MicroCode.exe --snapshot settings.png --settings-tab 2 --size 1000x700              :: หน้า Settings แท็บใดก็ได้
out\MicroCode.exe --snapshot chat.png --folder C:\repo --mode agent --seed-chat     :: ตัวอย่างบทสนทนา (ไม่บันทึก)
out\MicroCode.exe --snapshot run.png --fresh --folder C:\repo --mode agent --set ai_key_mode=local --set toolApprovalMode=yolo ^
    --agent-prompt "Fix the bug" --wait 30   :: รัน Agent กับโมเดลจริง (เช่น LM Studio) แล้วถ่ายภาพ
out\MicroCode.exe --snapshot pv.png --folder C:\repo --preview C:\repo\README.md --preview C:\repo\spec.pdf --wait 4   :: เปิดไฟล์ในแผง Preview
out\MicroCode.exe --snapshot ctx.png --folder C:\repo --mode agent --seed-chat --inspector-tab context            :: แท็บ Context / Preview / Plan / Tasks
out\MicroCode.exe --snapshot web.png --folder C:\repo --web http://localhost:5173/ --web-viewport iphone --web-eval web.json --wait 5
    :: WebApp Preview ในกรอบ iPhone — หน้าเว็บจาก WebView2 ถูกจับภาพมาประกอบ, web.json = innerWidth/UA/touch ที่หน้าเว็บรายงานจริง
out\MicroCode.exe --snapshot and.png --set androidSdkPath=C:\Android\Sdk --android-avd Pixel_7 --wait 150   :: บูต AVD แบบไม่มีหน้าต่างในแท็บ Android
out\MicroCode.exe --snapshot api.png --mode api --api-url http://127.0.0.1:8000/users --api-method GET --api-send --wait 3   :: API Studio ยิง request จริง
out\MicroCode.exe --snapshot br.png --mode browser --browser-url http://127.0.0.1:8000/ --browser-devtools console --browser-pick "button.buy" ^
    --browser-eval "document.title" --wait 4   :: Web Browser + DevTools (console|network|dom), เลือก element ผ่านตัวเลือกของหน้าเว็บจริง, รัน REPL
out\MicroCode.exe --snapshot hello.png --first-launch      :: การ์ดต้อนรับครั้งแรก (ปกติโหมด snapshot จะไม่แสดง)
```

ชุดทดสอบอัตโนมัติ (File Preview, ลิงก์ไฟล์, PDF, Markdown, LaTeX, กัน Save ทับไฟล์ binary + Consensus Engine / PNS 24/7: sandbox, git worktree จริง, daemon `pnsd` + Cell Mode + API Studio ยิง request จริงผ่าน loopback + การ์ดต้อนรับ) — สร้างไฟล์และ repo ทดสอบเองในโฟลเดอร์ชั่วคราว:

```bat
tests\run-tests.cmd
```

ภาพออกมาที่ความละเอียด 2x เทียบกับภาพ Retina ของ macOS ได้ตรงๆ

โหมด `--snapshot` ใช้โฟลเดอร์ข้อมูลแยก (`%TEMP%\MicroCode-snapshot` หรือ `--data-dir <dir>`) จึงไม่แตะ settings / คีย์ / แชตจริงของผู้ใช้
`--fresh` ล้างโฟลเดอร์ทดสอบนั้น, `--set key=value` กำหนดค่าตั้ง, `--set-key provider=key` ใส่ API key, `--agent-prompt "..."` ส่งข้อความให้ Agent ทันทีที่เปิด,
`--consensus-run "..."` กด Run Consensus, `--pns-launch "..."` กด Launch 24/7 (ใช้คู่ `--agent-bar task:6` / `task:7` และ `--wait N`)
`--pns-launch` จะเปิด daemon `pnsd` แยกโปรเซส (ใช้ `--data-dir` เดียวกัน) ซึ่ง**รันต่อหลังภาพเสร็จ** — ปิดด้วยปุ่ม Stop pnsd หรือ `POST /pns/shutdown` (header `X-PNS-Token` จาก `<data-dir>\.microcode\pns\daemon.token`)

## สิ่งที่พอร์ตแล้ว

| ส่วน | ต้นฉบับ (Swift) | สถานะ |
|---|---|---|
| หน้าต่างหลัก, แถบข้างเลื่อนเปิด/ปิด 0.12s, ลากปรับความกว้าง 160–600 | `ContentView.swift` (`NativeSidebarSplitContainer`) | ✅ |
| แถบหัว 36pt (ขนาด regular/compact/tight/ultraTight), Run/Build/Preview/Console, Agent / Code Editor / More Mode | `WorkspaceUnifiedHeaderBar` | ✅ |
| ปุ่มหน้าต่างแบบ traffic lights ซ่อนอัตโนมัติ (โผล่เมื่อชี้มุมซ้ายบน 82×36) | `WindowTrafficLightsController` | ✅ |
| แถบข้าง Xcode: Project / Source Control / Search / Issues, ต้นไม้ไฟล์ 24pt, Filter | `XcodeEditorSidebar`, `AuthenticFileTree` | ✅ |
| แท็บไฟล์, breadcrumb, Inline Edit (Ctrl+K), ป้ายภาษา, Markdown Rendered/Source, CSV/TSV Table/Source, รูป / PDF / ไฟล์ binary เปิดเป็น preview แบบอ่านอย่างเดียว (กด Save ก็ไม่เขียนทับ) | `EditorArea`, `CodeEditor` | ✅ |
| ตัวแก้โค้ด: ไฮไลต์ ~40 ภาษา, เลขบรรทัด, ไฮไลต์บรรทัดปัจจุบัน, auto-indent | `SyntaxHighlightedCodeView`, `LineNumberRulerView` | ✅ |
| Console: OUTPUT / TERMINAL / PROBLEMS / ANALYSIS, รันโค้ดจริง | `DebugArea` | ✅ |
| หน้า Welcome: Projects / Templates / AI Architect / Settings | `WelcomeScreen` | ✅ |
| Playground (Editor, Output, Auto-run, Hot Reload, Run) | `PlaygroundView` | ✅ |
| Agent: หน้าว่าง + กล่องพิมพ์ (+, Connect AI, Scope Lock, Local, Smart, Agent, ไมค์ = Windows Voice Typing, ส่ง/หยุด/คิว), คำตอบสตรีมสดระหว่างใช้เครื่องมือ | `AIAgentView` | ✅ |
| เมนูเลือกโมเดลแบบ Mac: Enterprise / Subscription / BYOK (ทุกเจ้า + Fetch Live Models + Custom ID) / Local LLM (สแกน Ollama 11434, LM Studio 1234/1235, llama.cpp 8080, vLLM 8000, Jan 1337 พร้อมกัน) / ACP / Dotmini Cloud (โมเดลสดจาก microcode.dotmini.net/v1 แยกตามผู้ให้บริการ + ราคา ฿/1M) | `presentNativeModelMenu` | ✅ |
| แนบไฟล์/รูป (ปุ่ม +, วาง Ctrl+V, ลากวาง), @mention ไฟล์ในโปรเจกต์ (popup), คำสั่ง / ทั้ง 19 ตัวของ Mac (popup), โหมด Plan + การ์ด Plan Review (Approve Plan & Proceed / Reject) | `SlashCommandService`, `approvalActionCard` | ✅ |
| Agent ข้อความ: ฟองผู้ใช้, Thought for Ns, แถวเครื่องมือ, การ์ดโค้ด (Editor/Copy), ตาราง, ปุ่ม คัดลอก/ลองใหม่/ย้อนกลับ/ลบ, จุดสามจุดตอนรอ | `RichMessageRow`, `AICellContentHost`, `NativeCodeBlockView` | ✅ |
| Agent ใช้เครื่องมือชื่อเดียวกับ Mac: list_directory_tree, file_read, multi_file_read, grep_search, file_search, find_symbol, git_status, web_fetch (กัน file://, link-local, cloud metadata และ bridge 18888), file_write, replace_in_file, multi_replace_in_file, patch_file, apply_patch (Codex V4A + unified diff, ทั้งหมดหรือไม่เขียนเลย, คง CRLF/LF เดิม), create_directory, rename_file, shell, read_skill (จำกัดในโฟลเดอร์งาน), แถว "Analyzed / Edited +A −R / Ran", การ์ดอนุมัติในแชต (Reject / Always Allow / Approve), Scope Lock ใช้งานจริง, จุดย้อนกลับคืนไฟล์ (Restore Checkpoint), XML tool bridge สำหรับโมเดลที่ไม่มี function calling | `AgentService`, `AgentToolBox`, `ToolApprovalView` | ✅ (ยังไม่ได้ทดสอบกับโมเดลจริง — เปิด LM Studio server หรือ login Dotmini แล้วทดสอบได้ทันที) |
| Rules หลายแพลตฟอร์มแบบ Mac: `AGENTS.md` (+ ในโฟลเดอร์ย่อย, `@import`), `CLAUDE.md` / `.claude/CLAUDE.md`, `.cursorrules`, `.cursor/rules/*.mdc` (globs / alwaysApply), `.windsurfrules`, `.clinerules`, Copilot, Zed, TX Code, `.microcode` และ `~/.microcode/rules` — ใส่ใน prompt ตามไฟล์ที่เปิดอยู่ (งบ 800 token) และแสดงในแท็บ Context · **Lifecycle hooks** `pre_tool` / `post_tool` / `pre_finish` จาก `.microcode/hooks.json`, `.cursor/hooks.json`, `.claude/settings.json` (รูปแบบ Claude Code `PreToolUse` / `PostToolUse` / `Stop` ใช้ได้ตรงๆ) — pre_tool ห้ามเครื่องมือได้, post_tool ส่งผลกลับให้โมเดล, pre_finish ที่ล้มส่ง Agent กลับไปแก้ 1 รอบ; ต้องกด **Trust** ต่อ workspace ก่อน (ผูกกับ SHA-256 ของไฟล์ config แก้ไฟล์แล้วถามใหม่) | `MultiPlatformRulesEngine.swift`, `WorkspaceTrustService.swift` | ✅ (ทดสอบ 53 ข้อ รวม tool loop จริงกับเซิร์ฟเวอร์ OpenAI-compatible บน loopback) |
| **MCP client** (Hyper-Mesh): อ่าน server จาก `~/.microcode/mcp.json`, Cursor, Windsurf, Codex, Antigravity (+ plugins), Claude Code / Claude Desktop / Claude plugins และ `.mcp.json` / `.cursor/mcp.json` / `.vscode/mcp.json` ในโปรเจกต์ (ของโปรเจกต์ต้องกด Trust ก่อน) · transport stdio (รองรับ `npx` / `.cmd` บน Windows) และ Streamable HTTP (JSON / SSE, `Mcp-Session-Id`, header, bearer เข้ารหัส DPAPI ต่อ origin) · probe เบื้องหลังแล้ว cache รายการเครื่องมือ, server stdio พักหลัง probe และตื่นเมื่อถูกเรียก, ตอบ `roots/list` / `ping` · Agent เห็นเครื่องมือเป็น `mcp__<server>__<tool>` (เลือก 12 ตัวที่เกี่ยวกับคำสั่ง) + `mcp_orchestrator` (status / connect / search_tools / restart) · แท็บ Settings → MCP Servers แสดงสถานะ, Start/Stop/Restart/Remove, เพิ่ม server · ปิดแอปแล้ว server ถูกหยุดด้วย | `ExternalMCPManager.swift`, `AgentEcosystemConfigView.swift` | ✅ (ทดสอบ 38 ข้อกับ server จริง: Python stdio + HTTP บน loopback + tool loop) — OAuth sign-in ของ remote server และ `synthesize` ยังไม่มี |
| ข้อความ error อ่านง่ายพร้อมปุ่มแก้ (401 คีย์ผิด, 402 เครดิตหมด, 429, 5xx, เน็ตหลุด) | `parseErrorMessage` | ✅ |
| Cell Mode (เขียนใหม่ตาม `NotebookView.swift` ปัจจุบัน): sidebar แบบ GroupBox (Cell Sheets, kernel + เลือก Python/venv, Data Files นำเข้า/สร้าง CSV/เปลี่ยนชื่อ/ลงถังขยะ/Insert Loader Cell/Sync จากโปรเจกต์, Run… by Color/Tag), toolbar 28pt (Python pill, แคปซูล [+ ▶ ▶▶ ▾], DAG, Compute, Vars, App, Open, Export, จำนวนรัน, โมเดล, Agent), การ์ด cell แบบ Mac ([n] + ปุ่มรัน, ภาษา 13 ภาษา, compute ต่อ cell, tag, สี 14 แบบ + กำหนดเอง, ป้าย Stale/ปลายทาง DAG, เวลา/หน่วยความจำ, ประวัติเวอร์ชัน + Restore, ยุบ/ย้าย/ลบ), `# @param` เป็น slider/ปุ่ม/สวิตช์, แบนเนอร์ diff เมื่อ AI แก้ (Accept/Revert), Markdown cell (Edit/Render, `{{ ตัวแปร }}`, LaTeX), คิวรันทีละ cell + Reactive DAG, kernel Python อุ่นต่อ sheet (stream สด, หยุดได้โดยตัวแปรไม่หาย, ตัวแปร/RAM/CUDA, DataFrame → ตาราง Table/Chart/Stats + SQL/CSV, จับกราฟ matplotlib/PIL/plotly/IPython display และไฟล์ที่ cell เขียน), SQL บน DataFrame สด, R/Julia/Rust/Go/C++/Java/C#/R Markdown/LaTeX ผ่าน toolchain ในเครื่อง, การ์ด output (log, Auto-Fix/Ask, กราฟ+Zoom, PDF, Markdown/TeX, HTML → แท็บ WebApp Preview), แถบตัวแปรสด, โหมด App (dashboard), ไฟล์ .mic (LZFSE แบบเดียวกับ Mac) / .ipynb / .mcnb / .py `# %%`, Open in Colab, autosave | `NotebookView.swift`, `DataFrameView.swift`, `KernelClient.swift`, `SharedMemoryService.swift`, `MicFormat.swift` | ✅ (ทดสอบ 58 ข้อ: kernel, pandas, SQL, C++, ไฟล์, เครื่องมือ cell_*) — Ardium/Objective-C รันได้เฉพาะ Mac, compute ระยะไกล (Colab/MicroCode Cloud/SSH) และ Shared Memory ยังไม่มีบน Windows, การถอด .mic ที่บีบอัดแบบ FSE ของ Mac ยังไม่ได้ทดสอบกับไฟล์จริงจาก Mac |
| Notebook Agent (แผงขวาของ Cell Mode ตาม `NotebookAIPanel.swift`): หัว "Agent · N cells ▾" (ทั้ง sheet / เฉพาะ cell ที่เลือก, Quote cell), แถบ error + Auto-Fix, หน้าเริ่มพร้อมคำแนะนำภาษาไทย, ข้อความแบบ IDE (thought, timeline ของ tool, Markdown/TeX, code block + Insert/Apply/Run/Copy), composer (+ แนบ, @ ตัวแปร/@Cell#, Agent/Ask, โมเดล + บทบาท 9 แบบ, ส่ง/หยุด), Agent cell ในหน้า, เครื่องมือ `cell_list/read/create/update/delete/run` บน tool loop เดียวกับ Agent หลัก | `NotebookAIPanel.swift`, `CellAIAgentEngine.swift`, `AgentToolBox.swift` (Cell tools) | ✅ (เครื่องมือ cell_* ทดสอบอัตโนมัติ; **ยังไม่ได้ทดสอบกับโมเดลจริง**) |
| API Studio (More Mode → API Client): แถบหัว (Scan Routes, Load .env, Code Snippet, Exit to Code), sidebar History / Collections / Environments + ค้นหา, แถบ request (method 7 แบบ, URL — วาง cURL แล้วนำเข้าให้เอง, Send, Save / Export / Import cURL), แท็บ Body (เลือก Content-Type) / Headers / Params / Auth (Bearer / Basic / API Key ใน header หรือ query), ตัวแปร `{{var}}` จาก environment, response (สถานะ · เวลา · ขนาด, Body แบบ pretty JSON / Headers / Raw / AI Tests = เช็ค status, latency SLA 1500 ms, body, รูปแบบ JSON, Content-Type), สแกน route จากโค้ด (FastAPI/Flask, Express, Next.js app router, Axum, Go), นำเข้า `.env` เป็น environment "Project (.env)", code snippet cURL / Swift / TypeScript / Python / Rust, ประวัติและ collection แยกต่อโปรเจกต์ | `APIClientView.swift`, `APIClientService.swift` | ✅ (ทดสอบ 24 ข้อ รวม request จริงผ่าน loopback) |
| Web Browser (More Mode → Browser): แท็บ (โหลดอยู่/ปิด/+), ‹ › ↻/✕, แถบ URL (กุญแจเมื่อเป็น https, พิมพ์คำค้นแล้วไป Google, localhost เปิดผ่าน http), Bookmark ⭐ + รายการ, History 20 รายการล่าสุด, ตัวเลือก element หลายจุด (Click-to-Prompt: คลิกในโหมด Inspect, Alt+คลิก, คลิกขวา, ลากกรอบ → ป้าย #n บนหน้าเว็บ + แถบ TARGETS → Send All ส่งให้ Agent ในรูปแบบเดียวกับ Mac), Developer Tools (Console + JS REPL, Network ของ fetch/XHR, DOM Source), เปิดในเบราว์เซอร์ภายนอก — ใช้ Edge WebView2 กับสคริปต์ telemetry ตัวเดียวกับ Mac | `IDEBrowserView.swift`, `IDEBrowserAutomationService` | ✅ (ทดสอบ 15 ข้อ + snapshot หน้าเว็บจริงที่มี console/fetch/picks) — เครื่องมือ `ide_browser` ของ Agent ยังไม่ได้พอร์ต |
| First-Launch Onboarding: การ์ดต้อนรับครั้งแรกทับหน้าต่าง — Continue with Google (ผ่านสะพาน 127.0.0.1:18888), Dotmini ID อีเมล/รหัสผ่าน, Continue without signing in; ไม่โผล่อีกเมื่อมีไฟล์ `.welcome_done` หรือ sign-in Dotmini อยู่แล้ว | `FirstLaunchWelcomeView.swift` | ✅ (ยังไม่ได้ทดสอบ sign-in ด้วยบัญชีจริง) |
| Settings แบบเต็ม 12 แท็บ (General, Editor, AI & Agent, Connect with Phone, Team Collaboration, Cloud GPU, Skills, MCP Servers, Tools, Extensions, Account & License, About), Cancel / Save Changes | `SettingsView` | ✅ |
| AI & Agent: 5 โหมด (Dotmini Cloud / Web Subscription / Direct API Key / Enterprise / Local LLM), ผู้ให้บริการ 15 เจ้า + Base URL + Fetch Models, คีย์เข้ารหัส DPAPI (ตัดช่องว่าง/ขึ้นบรรทัดที่ติดมาตอนวางคีย์) | `aiSettingsContent` | ✅ |
| Dotmini Cloud ใช้งานได้จริง: เข้าสู่ระบบ Dotmini ID ด้วยอีเมล/รหัสผ่าน, สร้างบัญชี, ลืมรหัสผ่าน, Continue with Google / เว็บเบราว์เซอร์ (ส่ง session กลับผ่าน 127.0.0.1:18888 เหมือน Mac), refresh token อัตโนมัติ, แผนและเครดิต, สมัครแพ็กเกจ/เติมเงินผ่าน Beam Checkout, Platform key + 1-Click Connect code, แชตผ่าน microcode.dotmini.net/v1 | `SupabaseAuthService`, `DotminiPlatformKeyService`, `MicroCodeLicenseSettingsView` | ✅ (ยังไม่ได้ทดสอบด้วยบัญชีจริง) |
| Skills: อ่าน SKILL.md จาก ~/.microcode, ~/.agents, ~/.codex, ~/.claude และโปรเจกต์ เปิด/ปิดได้, Agent โหลดผ่านเครื่องมือ read_skill | `AgentSkillsView` | ✅ |
| ธีม 40 แบบ (สีดึงอัตโนมัติจาก `AppState.swift`) | `AppTheme` | ✅ |
| เมนูบาร์ macOS (กด Alt), คีย์ลัดทั้งหมด | `MicroCodeApp.swift` commands | ✅ |
| แผงขวา Inspector (Ctrl+I): Context (ไฟล์ที่เปิด, ไฟล์ที่ Agent อ่าน/แก้, ไฟล์แนบ, rules/skills) · Preview · Plan · Tasks, ลากปรับ 220–760, ดับเบิลคลิกคืนค่า, อัปเดตตาม Agent สด | `AgenticContextInspector` | ✅ |
| Preview Dock แบบ Mac: แถบแท็บ WebApp Preview · iOS Sim · Android Emu · ไฟล์ · diff (ปิดได้, ปุ่ม + เพิ่ม, ลากไฟล์มาวาง), เปิดเอกสารแล้วแท็บ runtime ที่ว่างอยู่หลบให้, ปุ่ม "Preview ▾" บนหัวเปิด/ปิดแผงและมีเมนูอุปกรณ์ | `EmbeddedDeviceDockView`, `DevicePreviewHeaderMenu` | ✅ |
| WebApp Preview: Edge WebView2 ฝังแบบ native (ไม่ใช้ SDK/NuGet — runtime มากับ Windows 11), แถบ ‹ › ↻ · Viewport (Responsive + breakpoint 320–1440 ลากขอบปรับได้, iPhone, iPhone Duo นอก/ใน, iPad, MacBook, หมุนจอ, ซ่อนกรอบ, Fit/100%) · URL + จับ dev server อัตโนมัติ · Inspect เลือกจุดบนหน้าเว็บส่งให้ Agent · Port radar (Preview/เปิดเบราว์เซอร์/Kill) · Build ▶ รัน `npm/pnpm/yarn/bun run dev` แล้วเปิด URL ที่มันพิมพ์ · Live reload เมื่อบันทึก · แถบ error ของหน้าเว็บ + "Fix in Agent" · DevTools · Hard Reload | `EmbeddedWebAppPreviewView` | ✅ (CSS viewport ตรงเครื่องจริง: iPhone 402×874, iPad 834×1210, MacBook 1512×982 — ยืนยันจากหน้าเว็บ) |
| Android Emu: หาจาก Android SDK ที่มีอยู่ (ANDROID_HOME, Android Studio, หรือชี้ adb.exe ครั้งเดียว), รายการ AVD + มือถือ USB, บูต AVD แบบไม่มีหน้าต่าง, สตรีมจอผ่าน `adb exec-out screencap` ลงกรอบมือถือ, คลิก=แตะ ลาก=ปัด ล้อเมาส์=เลื่อน, Back/Home/Recents/พิมพ์ข้อความ, หยุด emulator, สร้าง AVD | `EmbeddedAndroidDeviceView` | ✅ (หน้าจอ/รายการ AVD ทดสอบแล้ว; การบูตและสตรีมยังไม่ผ่านบนเครื่องนี้) |
| iOS Sim: บอกตรงๆ ว่า Simulator ของ Xcode รันได้เฉพาะ macOS และเสนอดูเว็บแอปในกรอบ iPhone หรือใช้ Android แทน | `EmbeddedAppleSimulatorView` | ➖ ทำไม่ได้บน Windows |
| File Preview: โค้ด (breadcrumb, #L ช่วงบรรทัด, Diff กับ git HEAD, Copy, Open in Editor), Markdown (Preview/Raw), HTML/SVG (Live Preview → WebApp tab), รูป (ซูม −/%/+/Fit, Ctrl+ล้อ, ลากเลือกหลายจุดพร้อมโน้ตส่งให้ Agent), PDF native ผ่าน Windows.Data.Pdf (Continuous/Single Page, เรนเดอร์เฉพาะหน้าที่เห็น), CSV/TSV เป็นตาราง, .diff/.patch, diff ของ Agent + Split View, ไฟล์ binary (ไฟล์ที่รันได้ เช่น .exe .bat .ps1 จะไม่ถูกเปิดจาก preview) — ทุกแท็บโหลดใหม่เองเมื่อไฟล์เปลี่ยน | `InteractiveCodePreviewView`, `InteractivePDFPreviewView`, `InteractiveImagePreviewView` | ✅ |
| คลิกชื่อไฟล์ในแถวเครื่องมือ / การ์ดแก้ไฟล์ / ไฟล์แนบ / ป้าย +N −M / Split Diff → เปิดในแผง Preview แบบ Mac | `openTargetFileInPreviewDock`, `openDiff` | ✅ |
| Markdown: หัวข้อ (# และ ===), ลิสต์ซ้อน + checkbox, ตาราง GFM จัดซ้าย/กลาง/ขวา, quote + GitHub alerts ([!NOTE] ฯลฯ), code block ไฮไลต์ (Editor/Copy), รูป (ในเครื่อง/เว็บ/badge), ลิงก์ไฟล์และ `file.py` → Preview, HTML แบบ README (`<p align=center>`, `<img>`, `<a>`), front matter, ~~ขีดฆ่า~~, autolink | `RenderedMarkdownDocumentView`, `MarkdownAttrCache` | ✅ |
| LaTeX วาดเองแบบ native (ไม่ใช้ WebView/MathJax): `$…$`, `\(…\)`, `$$…$$`, `\[…\]`, `\begin{align/cases/pmatrix…}`, ```` ```math ````; เศษส่วน, ราก, ∑/∫/lim, matrix, cases, accent, `\mathbb` ฯลฯ, `\text{}` ภาษาไทย, ปุ่มดู source / คัดลอก LaTeX | `LaTeXBlockView` | ✅ |
| Task editor (Checklist / Spec / Walkthrough / Logs / Cost / Audit), Walkthrough, แผง Implementation Plan + การ์ดอนุมัติ, การ์ด diff (Revert/Restore) + Split Diff | `taskEditorView`, `PendingChangeCard` | ✅ |
| Consensus Engine (Task → Consensus): Builder แก้โค้ดใน sandbox copy ของโปรเจกต์ → Auditor เขียนเทสต์ใน `.consensus/` และบอกคำสั่งรันทีละเทสต์ → MicroCode รันเองแล้วตัดสินจาก exit code (ไม่เชื่อคำตอบโมเดล) + สแกนแบบ Mac (secret / SQL injection / Swift force unwrap) → โหวต Strict / Non-strict → apply เข้าโปรเจกต์เฉพาะตอนผ่าน (Auto-apply หรือกด Apply / Override); ไม่ทับไฟล์ที่ผู้ใช้แก้ระหว่างรัน, เคารพ Scope Lock, Auditor แก้โค้ด Builder ไม่ได้ (ถูกคืนค่าก่อนรันเทสต์), คำสั่ง shell ขออนุมัติตามโหมด Safe/Smart/Full Auto | `ConsensusEngine.swift`, `ConsensusEngineView.swift` | ✅ (pipeline ทดสอบอัตโนมัติ + กด Run ในแอปจริงกับโมเดลที่ต่อไม่ติด; **ยังไม่ได้รันกับโมเดลจริง**) |
| PNS 24/7 (Task → PNS 24/7, `/pns <งาน>`): mission → planner แตก subtask (ล้มเหลว → แผนสำรอง 3 fiber แบบ Mac) → motor fiber รันใน git worktree แยกบน branch `pns/auto-*` → verify command → commit บน branch หรือ 3-way merge เข้า working tree (`git merge-file --theirs` = กติกา Mac), owned-path lease, retry, Hebbian synapse, REM → playbook / inhibition, spinal reflex, homeostasis จากสถานะไฟ/แบต (Windows ไม่มี thermal state), daemon `pnsd` (`MicroCode.exe --pns-daemon`, 127.0.0.1 + token) ที่**รันต่อหลังปิดแอป**, เปิดตอน sign-in (HKCU Run แทน launchd) | `PNSOrchestrator.swift`, `PNSMotorWorktreePlexus.swift`, `PNSGanglionRouter.swift`, `PNSModels.swift`, `PNSNeuralDashboardView.swift` | ✅ (worktree / merge / daemon / mission ทดสอบจริง; **fiber ที่ทำงานสำเร็จกับโมเดลจริงยังไม่ได้ทดสอบ**; MCP tract ว่างเพราะยังไม่มี MCP client) |

## ยังไม่ได้พอร์ต

Remote Explorer (SSH), Science, Embed & IoT Studio, Extension Studio, เครื่องมือ `ide_browser` ของ Agent,
Agent: sub-agents, MCP server ของ MicroCode เอง + OAuth ของ remote MCP, ACP, `/arx` `/compare` `/squad`,
บริการเบื้องหลังของแท็บ Settings: Phone Companion, Realtime Collaboration, Cloud GPU, MCP server, Web Subscription login ของ ChatGPT/Claude/Gemini (หน้าจอมีแล้ว แต่ระบบยังไม่ทำงานบน Windows),
LSP / autocomplete, Collaboration, terminal แบบ ConPTY — โหมดที่ยังไม่พอร์ตจะแสดงหน้า "being ported"

## สิ่งที่ "เหมือน 100%" ไม่ได้ตามกฎหมาย และตัวที่ใช้แทน

| macOS | Windows | เหตุผล |
|---|---|---|
| SF Symbols | Segoe Fluent Icons (ไอคอนระบบ Windows 11) + เวกเตอร์วาดเองสำหรับตัวที่ไม่มี (เช่น brain) | Apple อนุญาต SF Symbols เฉพาะบนแพลตฟอร์ม Apple |
| SF Pro | Segoe UI | เหตุผลเดียวกัน |
| SF Mono | Consolas | เหตุผลเดียวกัน |
| ⌘ / ⌥ / ⌃+เลข | Ctrl / Alt / Alt+เลข (เช่น Ctrl+R รัน, Alt+1…9 สลับโหมด) | ธรรมเนียม Windows |
| เมนูบาร์บนสุดของจอ | กด Alt เพื่อแสดงเมนูในหน้าต่าง | Windows ไม่มีเมนูบาร์ระบบ |
| กรอบอุปกรณ์ PNG ของ Apple (iPhone/iPad/MacBook bezel) | กรอบวาดเป็น vector สัดส่วนเดียวกัน (จอ, ขอบ, มุมโค้ง, Dynamic Island) | ภาพอุปกรณ์ของ Apple ไม่ได้อนุญาตให้ใช้ในแอป Windows |
| WKWebView | Edge WebView2 (มากับ Windows 11) | engine เว็บของระบบ Windows ใช้เฉพาะแสดงหน้าเว็บที่ preview — ตัว IDE ยังเป็น native WPF |
| iOS Simulator (Xcode) | ไม่มี — แท็บ iOS Sim อธิบายและพาไปดูเว็บในกรอบ iPhone | Xcode/Simulator มีเฉพาะ macOS |

## โครงสร้าง

```
src/Core      UI.cs (HStack/VStack/Spacer/Button/เมนูแบบ NSMenu), Theme.cs, ThemeTable.g.cs, Sym.cs, AppState.cs, Native.cs
src/Editor    CodeEditorView.cs, Highlighter.cs
src/Views     MainWindow.cs, XcodeSidebar.cs, FileTreeView.cs, EditorArea.cs (+ MarkdownView), MathView.cs (LaTeX), PdfRender.cs, WelcomeScreen.cs, ModeViews.cs, Settings.cs,
              ApiStudio.cs (API Studio + บริการ HTTP/cURL/route scan), FirstLaunch.cs (การ์ดต้อนรับครั้งแรก), IdeBrowser.cs (Web Browser + DevTools + ตัวเลือก element)
src/Preview   WebView2.cs (WebView2 แบบ COM ตรง), WebAppPreview.cs, DeviceFrames.cs (กรอบอุปกรณ์วาดเอง), DevRuntime.cs (port + dev server),
              AndroidPreview.cs (adb/emulator), DeviceDock.cs (แถบแท็บ Preview), FileViews.cs (หัวแถบ preview ไฟล์แบบ Mac)
src/Notebook  NbView.cs (Cell Mode: sidebar/toolbar/คิวรัน/ไฟล์), NbCell.cs (การ์ด cell + output + ตาราง DataFrame), NbAgent.cs (แผง Agent + เครื่องมือ cell_*),
              NbKernel.cs (kernel Python + ภาษาอื่น), NbModel.cs (โมเดล + .mic/.ipynb/.mcnb/.py), NbEngines.cs (@param, DAG), LzfseDecoder.cs
src/Agent     Agent.cs (หน้า Agent), AgentRunner.cs (tool loop + สตรีม), AgentPanels.cs (Plan/Task/Walkthrough), DiffViews.cs, Inspector.cs (แผงขวา + File Preview),
              AIConfig.cs (โหมด/คีย์/endpoint/error), Dotmini.cs (Dotmini ID, Platform key, Cloud models, สะพาน 18888), Skills.cs, RulesEngine.cs (rules หลายแพลตฟอร์ม + hooks + Workspace Trust), Mcp.cs (MCP client),
              Consensus.cs (Consensus Engine + sandbox / git / การอนุมัติของ run แยก), Pns.cs (PNS 24/7: worktree, mission, daemon pnsd), PnsView.cs
tests         PreviewTests.cs + AgentPlatformTests.cs + NotebookTests.cs + StudioTests.cs + HarnessTests.cs + McpTests.cs + run-tests.cmd (คอมไพล์อ้างอิง out-dev\MicroCode.exe แล้วรันทุกชุด)
tools         extract_themes.py (ดึงสีธีมจาก Swift), icns_to_png.py + MakeIco.cs (ไอคอนแอป), GlyphAtlas.cs (ตารางไอคอน Segoe)
```

สร้างตารางสีธีมใหม่เมื่อ `AppState.swift` เปลี่ยน:

```bat
python tools\extract_themes.py ..\..\MicroCode\Models\AppState.swift src\Core\ThemeTable.g.cs
```

ข้อมูลผู้ใช้เก็บที่ `%APPDATA%\MicroCode` (settings.json, chats.json, notebooks.json, cloud-models.json, checkpoints\, api-client\<โปรเจกต์>\ ของ API Studio, .welcome_done); API key, Platform key และ session ของ Dotmini เข้ารหัสด้วย Windows DPAPI
settings.json เขียนแบบรวมค่า (อ่านไฟล์ล่าสุด → ใส่เฉพาะค่าที่หน้าต่างนี้เปลี่ยน → เขียนผ่านไฟล์ชั่วคราวแล้วสลับ) เปิดหลายหน้าต่างพร้อมกันก็ไม่ทับคีย์กัน
PNS เก็บที่ `~/.microcode/pns` เหมือน Mac (missions.json, synaptic_weights.json, procedural_playbooks.json, semantic_invariants.json, synaptic_wal.jsonl, daemon.token / .port / .pid, pnsd.log, worktrees\);
sandbox ของ Consensus อยู่ที่ `%TEMP%\MicroCode-Sandbox` และถูกลบเมื่อรันจบ (การเปลี่ยนแปลงถูกเก็บในหน่วยความจำจนกว่าจะ Apply)

© Dotmini Company Limited — อยู่ภายใต้ LICENSE ของ repository นี้
