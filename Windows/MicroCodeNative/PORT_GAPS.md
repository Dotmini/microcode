# MicroCode for Windows — รายการที่ยังไม่ครบ / ยังไม่เหมือน macOS

ตรวจเมื่อ 21 พ.ย. 2026 เทียบกับโค้ด macOS ใน `MicroCode/` ของ repo นี้ (branch `windows/native-port` @ `ef4794d`)

**ขนาดโค้ด:** macOS ≈ 267,000 บรรทัด Swift (Views 114k, Services 129k) · Windows ≈ 29,000 บรรทัด C#
ตัวเลขนี้ไม่ได้แปลว่าพอร์ตไปแล้ว 11% เพราะ C# ฝั่ง Windows เขียนแน่นกว่า แต่บอกได้ว่ายังเหลืองานอีกมาก

**สัญลักษณ์:**
- ✅ พอร์ตแล้วและทดสอบแล้ว
- 🟡 มีบางส่วน
- ⚪ มีแค่หน้าจอ ระบบเบื้องหลังยังไม่ทำงาน
- ❌ ยังไม่มีเลย
- ➖ ทำบน Windows ไม่ได้

---

## A. MicroCode AI / Agent

### A1. MicroCode AI (แอปแยกที่มีแต่ Agent)
macOS มีแอปรุ่นที่สองชื่อ **MicroCode AI** (bundle `com.dotmini.microcode.ai` หรือรันด้วย `--standalone-ai`, `MicroCodeApp.swift` `AppEdition`)
- เปิดมาเป็นโหมด Agent อย่างเดียว ซ่อน Code Editor และโหมดอื่นทั้งหมด
- ใช้ backend พอร์ต 3001
- ส่ง header `X-Dotmini-Client: microcode-ai`
- มีการแจ้งเตือนภาษาไทยว่า "MicroCode AI กำลังทำงานต่อเบื้องหลัง"
- **Windows: ❌** ยังไม่มีรุ่นนี้ ทำได้โดยใช้ exe ตัวเดิมแล้วเปิดด้วย flag `--standalone-ai` หรือตั้งชื่อ exe เป็น `MicroCode AI.exe`

### A2. Agent loop และ harness

| ส่วน | macOS | Windows |
|---|---|---|
| Tool loop + สตรีมคำตอบ, XML tool bridge, approval Safe/Smart/Full Auto, Scope Lock, checkpoint/restore | `AgentService.swift`, `AgentToolBox.swift` | ✅ |
| Plan mode + การ์ด Plan Review | `PlanModePolicy.swift`: ปิดเครื่องมือแก้ไฟล์ทุกตัวจนกว่าจะกด Approve | 🟡 มีการ์ดและโหมดอ่านอย่างเดียว แต่ไม่มี `create_plan` / `agent_plan` |
| แผนถาวรผ่าน Rust `agent_kernel` (ซิงก์ลง `.microcode/task.md`) | `AgentKernelClient.swift`, tool `agent_plan` | ❌ |
| ตรวจหลักฐานก่อนบอกว่าเสร็จ (อ่านไฟล์อย่างเดียวไม่นับว่าแก้แล้ว) | `AgentExecutionEvidence.swift` | ❌ |
| กันแก้ไฟล์ที่ถูกเปลี่ยนหลัง Agent อ่าน | `FileFreshnessGuard.swift` | ❌ (มีแค่ใน Consensus) |
| นโยบาย path (symlink, ห้ามออกนอก workspace) + Workspace Trust | `WorkspacePathPolicy.swift`, `WorkspaceTrustService.swift` | 🟡 จำกัดอยู่ใน workspace แต่ไม่มี trust gate |
| ปิดบังข้อมูลลับก่อนส่ง/บันทึก | `AgentPrivacyGuard.swift` | 🟡 redact แค่ไฟล์ task |
| บีบ context อัตโนมัติ / ลด token | `TokenOptimizer`, `HierarchicalContextCompiler`, `IdleStateCompactor`, `StateCompressionEngine`, `compactToolOutputsIfNeeded` | 🟡 มีแค่ `/compact` แบบกดเอง |
| Memory ข้ามแชต (semantic recall + embedding, สรุปแชต) | `AgentMemoryService.swift` (`agent_memory_v2.json`), `ProjectMemoryService.swift` | ❌ |
| Rules หลายแพลตฟอร์ม: `CLAUDE.md`, `.claude/CLAUDE.md`, `AGENTS.md` (รวมที่ซ้อนในโฟลเดอร์ย่อย), `.cursorrules`, `.windsurfrules`, `settings.json` | `MultiPlatformRulesEngine.swift` | ✅ (21 พ.ย.) |
| **Hooks** (`PreToolUse` / `PostToolUse` / `Stop` เป็นคำสั่ง shell) + Workspace Trust | `MultiPlatformRulesEngine.runHookShellCommand`, `WorkspaceTrustService` | ✅ (21 พ.ย.) |
| Log เครื่องมือแบบถาวร (JSONL) | `AgentToolTrace.swift` | ❌ |
| Flight Recorder (audit log เซ็นลายเซ็น) + หน้าดู | `FlightRecorder.swift`, `FlightRecorderView.swift` | ❌ |
| เก็บ transcript | `AgentTranscriptStore.swift` | 🟡 เก็บแชตใน `chats.json` |
| ล้าง output ที่สตรีมมา / Slop lint | `StreamingArtifactSanitizer.swift`, `SlopLint.swift` (tool `slop_check`) | ❌ |
| Background agent (ทำงานต่อหลังปิดหน้าต่าง + แจ้งเตือน) | `BackgroundAgentService.swift` (tool `background_agent`) | ❌ (มีแค่ PNS daemon) |
| Auto-commit / Auto-healer | `AutoCommitService.swift`, `AutoHealerService.swift`, `HealerAgent.swift` | ❌ (Auto-Fix มีเฉพาะใน Cell Mode และ WebApp Preview) |
| Shadow workspace (ลองแก้ในสำเนาก่อน) | `ShadowWorkspace*.swift` | 🟡 มีเฉพาะ sandbox ของ Consensus |
| Model router / SLM router (เลือกโมเดลเองตามงาน) | `AIModelRouter.swift`, `SLMRouter.swift` | ❌ |
| Usage / cost tracker + Cost Dashboard | `AIUsageTracker.swift`, `CostDashboardView.swift` | ❌ (มีแท็บ Cost ใน Task editor) |

### A3. เครื่องมือของ Agent (macOS 65+ ตัว · Windows 17 ตัว + cell_* 6 ตัว)

**มีบน Windows แล้ว:** `list_directory_tree`, `file_read`, `grep_search`, `file_search`, `file_write`, `replace_in_file`, `shell`, `read_skill`
และเพิ่มเมื่อ 21 พ.ย.: `multi_file_read`, `multi_replace_in_file`, `patch_file`, `apply_patch`, `create_directory`, `rename_file`, `find_symbol`, `git_status`, `web_fetch`
`cell_list/read/create/update/delete/run` ใช้ได้เฉพาะในแผง Agent ของ Cell Mode

**ยังไม่มี:**

| กลุ่ม | เครื่องมือ macOS |
|---|---|
| ไฟล์และโค้ด | `codebase_search` (semantic), `repo_map`, `get_diagnostics` |
| LSP | `lsp_hover`, `lsp_definition`, `lsp_completions`, `lsp_diagnostics`, `lsp_status` |
| เว็บ / ไฟล์แนบ | `attachment_read`, `inspect_image`, `extract_pdf`, `export_pdf` |
| วางแผน / Sub-agent | `agent_plan`, `create_plan`, `define_subagent`, `invoke_subagent`, `manage_subagents`, `send_message`, `swarm_orchestrator`, `background_agent` |
| คุม IDE | `editor_control`, `preview_control`, **`ide_browser`**, `api_studio`, `database_studio`, `device_runtime`, `visual_regression`, `playground_run`, `ardium_run` |
| Skills / MCP / PNS | `skill_engine` (match / read / run_script / crystallize), `mcp_orchestrator`, `mcp__local__*` (เครื่องมือจาก MCP server), `pns_nervous_system` |
| สื่อ | `generate_image`, `generate_video`, `generate_music`, `voice_coding` |
| Embedded | `embedded_list_hardware`, `embedded_compile`, `embedded_flash`, `embedded_serial_capture`, `embedded_serial_send`, `embedded_decode_crash` |
| วิทยาศาสตร์ | `science_inspect`, `alphafold_input_validate` |
| ควบคุมเครื่อง | `computer_use` (`NativeComputerUseService` + `AppleVisionEngine`): ต้องเขียนใหม่ด้วย UI Automation ของ Windows |

### A4. Slash commands (19 ตัว)

- **ทำงานแล้ว:** `/file`, `/compact`, `/clear`, `/model`, `/explain`, `/fix`, `/test`, `/refactor`, `/review`, `/learn`, `/pns`, `/search`, `/terminal`, `/help`, `/plan`, `/task`
- **❌ ขึ้นข้อความว่ายังไม่มีบน Windows:**
  - `/arx`: Portable .ARX Agent Capsule (`ARXCapsuleService.swift`)
  - `/compare`: ส่งคำถามเดียวกันให้ 2 โมเดลแล้วเทียบคำตอบ
  - `/squad`: ทีม agent หลายผู้เชี่ยวชาญ (`SubAgentHarness.swift`)
- **ต่างจาก Mac:** `/plan <งาน>` ของ Mac ใส่ prompt บังคับวิเคราะห์ 3 phase แล้วเรียก `create_plan` ส่วน Windows แค่เริ่มรันในโหมด plan

### A5. Skills

| ส่วน | macOS | Windows |
|---|---|---|
| ค้นหา SKILL.md ใน `~/.microcode`, `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills` และในโปรเจกต์ | ✅ | ✅ |
| เปิด/ปิดทีละ skill, นำเข้าไฟล์ | `AgentSkillsView.swift` | ✅ |
| Progressive disclosure (ส่งแค่ชื่อและคำอธิบาย แล้วโหลดตัวเต็มเมื่อใช้) | ✅ | ✅ (`read_skill`) |
| **Skill Router:** จัดอันดับ skill ตามคำถาม (ตัดคำไทย, stem, context boost, งบตัวอักษร, จัดกลุ่ม skill ที่ซ่อน, `$skill` ระบุตรงๆ) | `SkillRouter.swift` | ❌ ส่ง 60 ตัวแรกตามตัวอักษร |
| แบ่ง tier builtin / user / project | `SkillCatalogTier` | ❌ |
| `skill_engine` → `run_script` (รันสคริปต์ใน `scripts/` ของ skill) | ✅ | ❌ |
| `skill_engine` → `crystallize` (Agent สร้าง skill ใหม่จากงานที่ทำสำเร็จ) | ✅ | ❌ |

### A6. MCP

| ส่วน | macOS | Windows |
|---|---|---|
| **MCP client:** อ่าน `.cursor/mcp.json`, `.mcp.json`, `~/.cursor/mcp.json`, `~/.microcode/mcp.json`, plugin ของ Gemini; transport stdio + Streamable HTTP | `ExternalMCPManager.swift` (1,303 บรรทัด) | ✅ (21 พ.ย., `Mcp.cs`) — ยังไม่จัด server เข้า PNS tract ตามประเภท และยังไม่ restart อัตโนมัติเมื่อ server ล้ม |
| OAuth 2.1 ของ MCP (RFC 9728 discovery, PKCE, เก็บ token ใน Keychain) | `MCPAuth.swift`, `MCPAuthCenter.swift` | ❌ (ใช้ bearer token ที่เข้ารหัส DPAPI แทนได้) |
| สร้าง MCP server เป็น Python ให้อัตโนมัติ + hot-spawn | `ExternalMCPManager` (`.microcode/mcp/<name>.py`) | ❌ |
| `mcp_orchestrator` (Agent ติดตั้งหรือลงทะเบียน server เอง) | ✅ | ✅ status / discover / connect / search_tools / restart (authenticate, synthesize ตอบว่ายังไม่มี) |
| **MCP server ของ MicroCode** (ให้ client ภายนอกใช้เครื่องมือของ IDE: read/write/edit/search, playground, ide_browser, api_studio, database_studio, computer_use) | `MCPServer.swift` (1,799 บรรทัด) | ⚪ ปุ่ม Start ในหน้า Settings ขึ้นแค่ข้อความว่ายังไม่มี มีแต่สะพาน auth บน 127.0.0.1:18888 |
| แท็บ MCP ใน PNS 24/7 | ✅ | ⚪ ว่าง เพราะไม่มี client |

### A7. ACP (Agent Client Protocol)

| ส่วน | macOS | Windows |
|---|---|---|
| **ACP host:** ใช้ agent ภายนอกเป็น "โมเดล" ในแชต: Claude Code, OpenAI Codex, Gemini CLI (ย้ายไป Antigravity/AGY ให้อัตโนมัติ), Goose, OpenCode, GitHub Copilot, Cursor, Aider (CLI ที่ไม่ใช่ ACP ใช้ `-p` / `exec`) | `ACPHostService.swift` (1,937 บรรทัด), `ACPProtocol.swift` | ❌ เมนูโมเดลแสดงว่ายังไม่มี |
| หน้าอนุมัติสิทธิ์ของ ACP + แชต ACP | `ACPPermissionView.swift`, `ACPAgentChatView.swift` | ❌ |
| **ACP server:** `MicroCode --acp-server` ให้ Zed / JetBrains / Neovim / VS Code ใช้ MicroCode เป็น agent (sessions list/load/resume, โหมด agent/plan/ask, เก็บ transcript แบบ redact) | `ACPServerService.swift`, `ACPSessionStore.swift` | ❌ |
| Ghost text ผ่าน ACP / Agent Context Protocol bridge | `ACPGhostTextBridge.swift`, `AgentContextProtocolBridge.swift` | ❌ |
| หน้าตั้งค่า Agent Connections / Ecosystem | `AgentConnectionsView.swift`, `AgentEcosystemConfigView.swift` | ❌ |

### A8. Sub-agents และการทำงานหลาย agent

| ส่วน | macOS | Windows |
|---|---|---|
| SubAgent Harness (กำหนด/เรียก/จัดการ sub-agent, จำกัดความลึก, ส่งข้อความหากัน) | `SubAgentHarness.swift` (2,043 บรรทัด), `SubAgentSpawnPolicy.swift` | ❌ |
| แถว sub-agent ในแชต + หน้ารายละเอียด + Monitor | `InlineSubAgentViews`, `SubAgentDetailSheet`, `SubAgentMonitorView` | ❌ |
| Swarm / Squad / Compare | `swarm_orchestrator`, `/squad`, `/compare` | ❌ |
| Consensus Engine | ✅ | ✅ |
| PNS 24/7 | ✅ | ✅ (ไม่มี MCP tract) |

### A9. ผู้ให้บริการโมเดล

| ส่วน | macOS | Windows |
|---|---|---|
| Dotmini Cloud, Direct API Key (15 เจ้า), Local LLM (Ollama / LM Studio / llama.cpp / vLLM / Jan) | ✅ | ✅ (ยังไม่ได้ทดสอบกับบัญชีหรือโมเดลจริง) |
| **Web Subscription** (login ChatGPT / Claude / Gemini ผ่านเว็บ) | `SubscriptionAuthManager.swift` (2,128), `WebSubscriptionLoginSheet`, `ClaudeWebSessionBridge`, `LocalSubscriptionGatewayService` | ⚪ หน้าจอมีแล้ว แต่ใช้งานไม่ได้ |
| Enterprise (โปรไฟล์ Vertex / Bedrock / Azure ฯลฯ, Enterprise Connect Hub) | `EnterpriseConnectionProfiles.swift` (2,613), `EnterpriseAIAuthService`, `EnterpriseConnectHubView` | 🟡 มีแค่ช่องตั้งค่า |
| Local LLM Gateway (ให้มือถือหรือเครื่องอื่นในบ้านใช้โมเดลในเครื่อง) | `LocalLLMGatewayService.swift`, `LocalEcosystemDiscovery.swift` | ❌ |
| Model Browser + Catalog | `ModelBrowserSheet.swift`, `AIModelCatalog.swift` (2,145) | 🟡 มีเมนูโมเดล ไม่มีหน้า browser |

### A10. หน้าจอฝั่ง Agent อื่นๆ
- **❌ ยังไม่มี:**
  - Task Logs (`TaskLogsView`)
  - Context Provider (`ContextProviderView`)
  - Visual Regression dashboard
  - AI Trainer (`AITrainerView` + `MLTrainer`)
  - Platform Compatibility Inspector
  - Healer suggestion
- **✅ มีแล้ว:** Inspector (Context / Preview / Plan / Tasks), Task editor, Walkthrough, การ์ด diff

### A11. บั๊กที่เจอระหว่างตรวจ
1. **เมนูที่กดแล้วไม่ทำอะไรเลย:** Index Project, Import/Export .ARX Capsule ส่งคำสั่ง `agent:index` / `agent:exportArx` / `agent:importArx` ไปแล้ว แต่ไม่มีโค้ดรับ
   - **แก้แล้ว (ยังไม่ commit):** เปลี่ยนเป็นเมนูที่กดไม่ได้ และมีข้อความ "(not on Windows yet)"
   - ตัวฟีเจอร์จริงยังต้องพอร์ต: `RepoMapService`, `ARXCapsuleService`
2. **ปุ่ม "Document" ใน Playground** ไม่มีการทำงาน (`() => { }`)
   - **แก้แล้ว (ยังไม่ commit):** เอาปุ่มออก
   - ยังเหลือปุ่ม Data และ Preview ที่แค่สลับสถานะ ไม่มีเนื้อหาให้แสดง (ต้องพอร์ตจาก `PlaygroundView.swift`)

---

## B. IDE และโหมดต่างๆ

| ส่วน | macOS | Windows | ที่ขาด |
|---|---|---|---|
| หน้าต่าง, header, traffic lights, sidebar Xcode, ธีม 40 แบบ, เมนู | `ContentView`, `Workspace*` | ✅ | — |
| ตัวแก้โค้ด | `AuthenticEditor` + `SyntaxEngine` (7,428) | 🟡 ไฮไลต์ ~40 ภาษา | LSP, autocomplete popup, AI ghost text (`AIAutocompleteService`, `SuperTabEngine`), จุด error/warning ในบรรทัด, folding |
| LSP | `LSPManager`, `LSPClientService` (2,442) | ❌ | — |
| Debugger (breakpoint, step, ตัวแปร) | `DebugPanelView` (1,504), `DebugService` (987) | ❌ | — |
| Git | `GitPanelView`, `GitSettingsView`, `GitHistoryView`, `MergeConflictView` (1,337), `GitAuthService` | 🟡 status / commit | history, แก้ merge conflict, ตั้งค่าและ auth ของ git |
| Terminal | `AuthenticTerminal` (PTY จริง) | 🟡 redirect I/O | ConPTY (โปรแกรม interactive, สี, vim) |
| Find / Replace ทั้ง workspace | ✅ | ✅ | — |
| Playground | `PlaygroundView` (4,022) | 🟡 | Document / Data / Preview, cell ใน playground, stdin |
| Cell Mode | `NotebookView` (6,866) | ✅ | compute ระยะไกล (Colab / MicroCode Cloud / SSH), Shared Memory, Ardium ➖, .mic ที่บีบอัดจาก Mac ยังไม่ได้ทดสอบ |
| API Studio | ✅ | ✅ | tool `api_studio` ของ Agent |
| Web Browser | ✅ | ✅ | tool `ide_browser` ของ Agent |
| Preview Dock: WebApp / Android / ไฟล์ / PDF / รูป | ✅ | ✅ | iOS Sim ➖, Android boot/stream ยังไม่ผ่านบนเครื่องนี้ |
| Remote Explorer (SSH) | `RemoteXView` (2,779), `RemoteWorkspaceManager`, `SSHConfigParser`, `RemoteFileBrowser`, `RemoteTerminalView` | ❌ placeholder | ทั้งหมด |
| Science | `ScienceModeView`, `ScienceService` | ❌ placeholder | ทั้งหมด |
| Scenario | `ScenarioView` (1,552) | ❌ placeholder | ทั้งหมด |
| Embed & IoT Studio | `EmbeddedStudioView` (5,757), `EmbeddedHardwareServices` (2,454), `EmbeddedEnvManager`, `EmbeddedToolsView`, `EmbeddedAIAgentPanel` | ❌ placeholder | ทั้งหมด (compile / flash / serial / decode crash) |
| Extension Studio + OpenVSX | `ExtensionStudioView` (2,351), `OpenVSXMarketplaceView`, `ExtensionManager`, `ExtensionHostService` | ❌ placeholder | ทั้งหมด |
| Database Studio | `DatabaseStudioView`, `DatabaseService` | ❌ placeholder | — |
| Container Studio | `ContainerView` (965), `ContainerService` (929) | ❌ placeholder | — |
| CI/CD Pipelines | `CICDPipelineView` (1,435), `CICDService`, `LocalPipelineRunner` | ❌ placeholder | — |
| Realtime Collaboration | `CollaborationView` (2,155), `CollaborationService` (5,803), `CRDTEngine` | ✅ host / join / mirror / realtime edit ด้วย ot1 (+ `fileBuffer` / 3-way merge สำหรับ client รุ่นเก่า) / room code ทุก route / invite `/join` + `microcode://collab` deep link (HKCU protocol, single instance, ถามยืนยัน) / browser editor แบบ opt-in / realtime CRUD ทั้งสองทาง / presence / follow / chat / web portal / relay / AI teammate + `@ai` | Bonjour discovery, QR, SSH tunnel (localhost.run), cursor ของเพื่อนใน editor, presence bar บน title bar; ต่างจาก Mac โดยตั้งใจ: การพิมพ์บนเครื่อง host ไม่ถูกเขียนลงดิสก์อัตโนมัติ (Mac เขียนทุก 250 ms) ต้อง Save เอง; ยังไม่รองรับ: ข้อความ IME ที่ยังพิมพ์ไม่จบตอน op จากคนอื่นเข้ามา; ยังไม่ได้ทดสอบข้ามเครื่อง / กับ Mac / กับ relay จริง / คลิกลิงก์ `/join` จากเบราว์เซอร์จริง |
| Connect with Phone | `PhoneCompanionService` (6,500+), `PhoneCompanionSettingsView` | ⚪ | — |
| Cloud GPU | `CloudGPUView`, `CloudGPUService`, `RemoteGPUService` | ⚪ | — |
| Team Tasks | `TeamTasksView`, `TeamTaskService`, `TeamIntegrationService` | ✅ บอร์ด + composer + Slack/Teams webhook + sync ในห้อง + contract ให้ Agent + ปุ่ม Team ใน Agent | ยังไม่ได้ยิง webhook จริง |
| Runtime / Python env / Node version | `RuntimeManagerView`, `PythonEnvSheet`, `NodeVersionPicker`, `ProjectRuntimeView` | 🟡 เลือก Python ใน Cell Mode | หน้าจัดการ runtime |
| Mobile dev bar / อุปกรณ์จริง / Store lifecycle / Asset matrix / Build report | `MobileDevCommandBarView`, `PhysicalDeviceSurfaceView`, `StoreLifecycleModalView`, `AssetMatrixModalView`, `BuildReportView` | ❌ | — |
| Keyboard shortcuts cheat sheet, Theme picker | `KeyboardShortcutsCheatSheetView`, `ThemePickerView` | 🟡 เลือกธีมได้ใน Settings | cheat sheet |
| Voice coding + TTS | `VoiceCodingService`, `TextToSpeechService` | 🟡 ไมค์ใช้ Windows Voice Typing | คำสั่งเสียง, TTS |
| First-launch onboarding | ✅ | ✅ | ยังไม่ได้ทดสอบ sign-in จริง |

---

## C. ลำดับที่แนะนำ
1. **แก้บั๊กใน A11:** งานเล็ก เมนูที่กดแล้วเงียบควรใช้งานได้หรือบอกเหตุผล
2. **Agent harness ที่กระทบทุกแชต:**
   - อ่าน `CLAUDE.md` / `AGENTS.md` / `.cursorrules`
   - hooks
   - เครื่องมือไฟล์ที่ขาด: `multi_file_read`, `apply_patch`, `git_status`, `web_fetch`, `create_plan`
   - Skill Router
   - บีบ context อัตโนมัติ
3. **MCP client** (stdio + HTTP + OAuth) แล้วตามด้วย MCP server
4. **ACP host** (Claude Code / Codex / Gemini CLI / Goose / OpenCode) แล้วตามด้วย `--acp-server`
5. **Sub-agents** (`define/invoke/manage_subagents`, `/squad`, `/compare`) และ memory ข้ามแชต
6. **MicroCode AI** รุ่นที่มีแต่ Agent (`--standalone-ai`)
7. โหมดที่ยังเป็น placeholder: Remote Explorer → Extension Studio → Database / Container / CI/CD → Science / Scenario → Embedded
8. ฝั่ง Editor: ConPTY terminal → LSP + autocomplete + ghost text → Git history / merge → Debugger

> หมายเหตุ: รายการนี้ตรวจจากการเทียบโครงสร้างโค้ด ชื่อไฟล์ เครื่องมือ และข้อความ "not available" ในโค้ด Windows ยังไม่ได้เปิดเทียบหน้าจอทีละหน้ากับเครื่อง Mac จริง
