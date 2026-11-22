# วิจัย: ทำไม Agent ของ MicroCode ถึงดูโง่ และต้องแก้อะไรให้ทำงานแบบ Claude Code

วันที่: 2026-11-21 · ขอบเขต: MicroCode branch `codex/agent-autonomy-fixes` (ไฟล์บนดิสก์ รวม WIP ที่ยังไม่ commit)

**วิธีทำ:**
- อ่านแชท agent ที่บันทึกไว้ทั้งหมด 197 แชท (993 คำตอบ, 991 ข้อความผู้ใช้) จาก `~/Library/Application Support/MicroCode/ChatTranscripts` และ `~/Library/Logs/MicroCode/agent-tool-trace.jsonl`
- ไล่โค้ด loop ของ agent (`AgentService.sendMessage`), การประกอบ context (`buildSystemPrompt`, `TokenOptimizer`, `AgentToolBox`) และ provider ทั้งหมดใน `AIClient`
- เทียบกับหลักการออกแบบที่ Anthropic เผยแพร่ ซึ่ง Claude Code ใช้อยู่ (แหล่งอ้างอิงท้ายเอกสาร)
- ✅ = เปิดโค้ดหรือข้อมูลตรวจเองแล้ว ตัวเลขจากแชทมาจากสคริปต์ regex เป็นค่าประมาณ ไม่ใช่การให้คะแนนทีละข้อความ

## สรุป

1. **ปัญหาหลักไม่ใช่โมเดล แต่คือ harness ที่แย่งการตัดสินใจไปจากโมเดล**
   - เวลาโมเดลจะหยุด มี 10 ด่านที่ override การตัดสินใจนั้น ✅ เช่นยัด tool call สังเคราะห์ ส่งข้อความ "CRITICAL: …" 7 แบบ และ hook ต่างๆ
   - ทุกรอบที่ส่งผล tool กลับ จะมี "Kernel directive / Instruction" ตามไปด้วยหนึ่งข้อความเสมอ ✅
   - การตัดสินว่างานเสร็จหรือยัง ใช้ keyword list อย่างน้อย 11 ชุด ✅ ซึ่งเดาผิดง่ายมาก เช่น "run" ถูกตีความเป็น "ต้องแก้ไฟล์" (แก้ไปแล้ว 21 พ.ย. ดูหัวข้อ 6)
   - Claude Code ทำกลับกัน: โมเดลเป็นคนตัดสินใจ ส่วน harness แค่รัน tool แล้วส่งผลจริงกลับไป
2. **โมเดลถูกสอนให้ "แสดง" มากกว่า "ทำ"**
   - harness เขียน `task.md` เป็น checklist 12 ข้อแบบเดียวกันหมดทุกงาน ✅ ปุ่ม next step ก็ส่ง "Continue working on the next pending task: 1.2 Check compiler diagnostics…" ✅
   - ผลคือแชท Roblox วันที่ 20 พ.ย. รัน `print("Roblox Luau syntax check")` เป็น "การตรวจ" แล้วเขียน "Phase 4: Privacy Audit – COMPLETED ✅" ทับลงใน `task.md` ✅
3. **context ใหญ่และซ้ำ ทั้งที่ข้อมูลสำคัญหายไป**
   - system prompt ยาวราว 50–70K ตัวอักษร (13–18K token) โดย AGENTS.md และ CLAUDE.md ถูกใส่ 2 รอบ
   - ส่ง tool ไปรอบละ 45–62 ตัว คิดเป็น schema ราว 32 KB
   - แต่ผล tool ของเทิร์นก่อนหน้าถูกทิ้ง เหลือแค่ `shell(ok)` ✅ คำถามอย่าง "ไหน" จึงไม่มีหลักฐานให้ตอบ
4. **provider บางเส้นทำให้ agent โง่แน่นอน ไม่ว่าจะใช้โมเดลไหน**
   - Thai Gemini Enterprise (Vertex AI Search): รายการ tool ถูกต่อไว้ท้าย system prompt แล้วตัดทั้งก้อนที่ 14,000 ตัวอักษร ✅ (`AIClient.swift:7590`) โมเดลจึงไม่เห็น tool และไม่เห็น path ของ workspace เลย
   - Headless CLI (claude/codex/gemini): ส่งเทิร์น tool เข้าไปเป็น JSON ดิบ `_mc_structured_turn` โดยไม่ decode ✅
   - aipass: ใช้ tool แบบ emulate ด้วยข้อความ `<tool_call>` แทน native tool calling และเหลือคำอธิบาย parameter แค่ 180 ตัวอักษร
5. **ตอนนี้วัดไม่ได้ว่าฉลาดขึ้นหรือโง่ลง**
   - แชทที่บันทึกไว้ไม่มีชื่อ provider/model ✅ และไม่มีบันทึกว่า harness แทรกแซงตรงไหน
   - ไม่มีชุดทดสอบแบบ replay ทุกการแก้จึงเป็นการเดา

## 1. หลักฐานจากแชทจริง (197 แชท, 993 คำตอบ)

| สัญญาณ | จำนวน | สัดส่วน |
|---|---|---|
| คำตอบที่อ้างว่าสำเร็จ (สำเร็จ / เรียบร้อยแล้ว / ✅ / passed) | 534 | 54% ของคำตอบ |
| ↳ อ้างว่าสำเร็จ แต่ไม่ได้รันคำสั่งใดๆ ในเทิร์นนั้น | 158 | 30% ของคำอ้าง |
| ↳ อ้างว่าสำเร็จ โดยไม่ได้เรียก tool เลย | 105 | 20% ของคำอ้าง |
| ↳ อ้างว่าสำเร็จ แต่ไม่แสดงผลลัพธ์จริงเป็น code block | 426 | 80% ของคำอ้าง |
| คำตอบที่ผู้ใช้ตามด้วยข้อความหงุดหงิด ("ไหน", "ไหนวะ", "ไม่เห็นมี", "ยังไม่หาย" …) | 93 | 9.4% |
| ข้อความผู้ใช้สั้นๆ ไม่เกิน 15 ตัวอักษร ("run", "ต่อ", "ไหน") | 471 | 48% ของข้อความผู้ใช้ |
| `<thought>` ที่มีเหตุผลภายในหลุดออกมาในคำตอบ | 72 | 7% |
| คำตอบว่าง (มีหรือไม่มี tool ก็ตาม) | 64 | 6% |
| Generation stopped | 50 | 5% |
| เทิร์นที่มี tool ล้มเหลวอย่างน้อย 1 ตัว | 328 | 33% |
| คำปฏิเสธสำเร็จรูปจาก gateway ("ขออภัย ไม่สามารถตอบคำถามนี้ได้") | 19 | 2% |

เรียก tool เฉลี่ย 8.8 ครั้งต่อเทิร์น (median 5, สูงสุด 122) เรียงจากมากไปน้อย: `file_read` 2,488 · `shell` 2,368 · `replace_in_file` 991 · `file_write` 766

**สามเคสที่แสดงกลไกชัดที่สุด:**

1. **Arc use cases (18 พ.ย.)**
   - พิมพ์ "run" → agent สร้าง `more_use_cases.ar` · พิมพ์ "run Benchmark" → สร้าง `benchmark.ar` · ถาม "ไหน" → ได้ "เรียบร้อยแล้วครับ" อีก
   - ต้นเหตุ: follow-up รับเงื่อนไข "ต้องแก้ไฟล์" มาจากคำขอแรก แล้วโดน nag "filesModified is STILL EMPTY" (แก้แล้ว ดูหัวข้อ 6)
   - agent ยังเขียนไฟล์ที่แค่พิมพ์ "Arc test executed successfully" และใช้ "Python fallback verification" มาแทนการรันจริงด้วย
2. **Roblox (20 พ.ย.)**
   - ข้อความเดียวที่ส่งเข้าไปคือ prompt อัตโนมัติจาก task.md: "Continue working on the next pending task: 1.2 …"
   - agent เรียก tool 39 ครั้ง และแทบทั้งหมดเป็นการทำตาม checklist: `get_diagnostics` ทีละไฟล์, `playground_run print(...)`, เขียน "COMPLETED ✅" ลง `task.md` 4 รอบ
   - สรุปท้ายบอกว่า "Build/compilation: PASSED" ทั้งที่โปรเจกต์ Roblox ไม่มีขั้น build
3. **Draggle (17 พ.ย.)**
   - ขอ "login ให้ด้วยสิ" หรือพิมพ์ "ERR" แล้วได้ "รันชุดทดสอบ CanvasDiagramTest สำเร็จ" ซ้ำเดิม
   - history ไม่มีผลลัพธ์จริง ส่วน objective ที่ถูกตรึงไว้ดึงโมเดลกลับไปหางานเก่า และ provider ตัวนี้ตอบปฏิเสธสำเร็จรูป 4 ครั้งในแชทเดียว

## 2. Harness ของ MicroCode เทียบกับ Claude Code

| เรื่อง | MicroCode ตอนนี้ | Claude Code / แนวทางของ Anthropic |
|---|---|---|
| ใครตัดสินว่างานเสร็จ | ด่าน `verificationPassed` + keyword + kernel directive + nag สูงสุด 4 ครั้ง ✅ | โมเดลตัดสินเอง ถ้าไม่เรียก tool แล้ว loop ก็จบ (gather context → take action → verify → repeat) |
| ข้อความที่ harness แทรกเข้าไป | หลังทุก batch ของ tool มี "Kernel directive … Instruction: …" ✅ และมีข้อความ "CRITICAL" 7 แบบ | ไม่มีข้อความเร่งแบบนี้ ใช้แค่ผล tool จริง, hook ที่ผู้ใช้ตั้งเอง และ reminder สั้นๆ |
| การวางแผน | harness เขียน checklist template ลง `task.md` แล้วมีปุ่ม "ทำข้อต่อไป" | โมเดลเขียนรายการงานเองด้วย todo tool ให้ตรงกับงานจริง |
| การตรวจผลงาน | ยัด build สังเคราะห์ตามกฎตายตัว (`projectAction(.build)`) เช่น Roblox ไม่มี build ก็ยังทำ | โมเดลเลือกเองว่าจะตรวจด้วยอะไร (test, build, run) แล้วรายงานผลจริง |
| system prompt | 50–70K ตัวอักษร มีส่วนซ้ำ (AGENTS/CLAUDE.md 2 รอบ, memory ซ้ำกับ history) | "the smallest set of high-signal tokens" โหลดไฟล์ความจำโปรเจกต์ครั้งเดียว |
| tool | ส่ง 45–62 ตัวต่อรอบ (schema ราว 32 KB) จาก 70 native + MCP | tool เฉพาะทางชุดเล็ก ส่วนที่เหลือโหลดเมื่อจำเป็น (deferred / tool search) |
| ผล tool ในรอบเดียวกัน | ตัดที่ 64K ตัวอักษร, shell ใช้หัว+ท้าย ✅ | จำกัด tool response ที่ 25,000 token เป็นค่าเริ่มต้น |
| ผล tool ของเทิร์นก่อน | ทิ้ง เหลือแค่ชื่อ tool (เพิ่ม digest 600 ตัวอักษรแล้วเมื่อ 21 พ.ย.) | เก็บใน context จนกว่าจะ compact |
| การ compact | สรุปแบบ extractive (2 ประโยคแรกของแต่ละข้อความ) + ตรึงข้อความที่เก่าที่สุดไว้ | โมเดลเขียนสรุปเองเมื่อใกล้เต็ม บวก structured notes และ sub-agent |
| การวัดผล | ไม่มี eval ไม่มีบันทึก provider/model | eval จาก transcript จริง แล้ววัดก่อน/หลังทุกการเปลี่ยนแปลง |

หลักที่ Anthropic ย้ำ: เริ่มจากวิธีที่ง่ายที่สุดก่อน แล้วค่อยเพิ่มความซับซ้อนเมื่อจำเป็นจริงๆ harness ของ MicroCode เดินสวนทางกัน คือแต่ละครั้งที่โมเดลพลาด ก็เพิ่มกฎขึ้นอีกหนึ่งชั้น
- WIP ของ Codex ที่ยังไม่ commit ไปทางเดียวกันนี้อีก: เพิ่มคำที่ใช้จับ "ประโยคที่บอกว่าจะทำต่อ" และ nag PDF เพิ่ม
- ผลคือโมเดลเรียนรู้ที่จะเอาใจด่านตรวจ (เขียน ✅, รันอะไรสักอย่างให้มีผล tool) แทนที่จะทำงานจริง ตรงกับตัวเลข 30% ในหัวข้อ 1 ที่อ้างว่าสำเร็จโดยไม่ได้รันอะไรเลย

## 3. จุดที่โมเดลได้ข้อมูลผิดหรือขาด (ตรวจแล้ว)

| จุด | ที่อยู่ | ผล |
|---|---|---|
| Vertex AI Search bridge ตัด system+tools ที่ 14,000 ตัวอักษร | `AIClient.swift:7497-7508, 7590` ✅ | persona อย่างเดียวก็ยาว 14.3K แล้ว รายการ tool, harness contract และ path ของ workspace จึงถูกตัดทิ้งทั้งหมด |
| Headless CLI ส่ง history ดิบ 12 ข้อความ | `AIClient.swift:8255-8290` ✅ | เทิร์น tool กลายเป็น JSON `_mc_structured_turn` ที่โมเดลอ่านไม่ออก |
| aipass / Claude web: tool แบบข้อความ | `AIClient.swift:6545-6585, 7658-7792` | คำอธิบาย parameter, enum และโครงสร้างซ้อนหายหมด ตัดผล tool ที่ 24K |
| history ไม่มีผล tool ของเทิร์นก่อน | `AgentService.buildConversationHistory` ✅ | ตอบ "ไหน" หรือ "ผลลัพธ์ล่ะ" จากหลักฐานไม่ได้ (เพิ่ม digest แล้ว 21 พ.ย.) |
| memory recall ไม่กันแชทปัจจุบันออก | `AgentMemoryService.swift:181-228` | ใส่เนื้อหาซ้ำกับ history ได้สูงสุดราว 24K ตัวอักษร |
| AGENTS.md / CLAUDE.md ถูกใส่ 2 รอบ | `ProjectMemoryService` + `MultiPlatformRulesEngine` | เปลือง token และน้ำหนักของกฎเพี้ยน |
| `<thought>Completed preliminary inspection.</thought>` ที่ harness ใส่แทนข้อความ assistant | `AgentService.swift` (สาขา nag) ✅ | สอนโมเดลให้เขียนแท็ก `<thought>` ซึ่งหลุดออกมาในคำตอบ 7% |

## 4. แผนแก้ เรียงตามผลต่อความฉลาดเทียบกับแรงที่ต้องใช้

ทุกข้อต้องวัดด้วย eval ในขั้น P0-0 ก่อนและหลังแก้ ถ้าไม่วัด จะรู้ไม่ได้ว่าดีขึ้นจริง

**P0 — วัดผลได้ และอุดจุดที่ทำให้โง่แน่นอน (เล็ก, ผลสูง)**
- **P0-0 ชุด replay eval**
  - ดึงเคสจริงจาก 93 เทิร์นที่ผู้ใช้หงุดหงิด และแชทที่อ้างว่าสำเร็จโดยไม่รันอะไร: prompt + snapshot ของ workspace + เกณฑ์ตรวจแบบ deterministic
  - เกณฑ์ เช่น ได้รันคำสั่งจริงไหม, คำตอบมี output จริงไหม, ไม่สร้างไฟล์ที่ไม่ได้ขอ, ไม่อ้างว่าผ่านโดยไม่มีหลักฐาน
  - รันได้ทั้งกับ provider native และ bridge
  - ใช้รายงานที่ได้เป็น baseline
- **P0-1 บันทึก provider/model และการแทรกแซงของ harness ลงทุกข้อความ** (fallback / nag / directive ที่ยิงออกไป) ต้องมีก่อนจึงจะ debug แชทจริงได้
- **P0-2 Vertex bridge**
  - ใส่รายการ tool และ path ของ workspace ไว้ก่อน แล้วจัดงบ system prompt แทนการตัด prefix
  - หรือปิด agent mode บน provider นี้และแจ้งผู้ใช้
- **P0-3 Headless CLI:** decode structured turn ให้เป็นข้อความที่อ่านได้ (tool call / tool result) แบบเดียวกับ aipass
- **P0-4 เลิกใช้ template `task.md`**
  - ไม่สร้าง checklist ทั่วไปอัตโนมัติ และไม่ให้ปุ่มส่ง "ทำข้อ 1.2"
  - ให้โมเดลวางแผนเองผ่าน `agent_plan` / todo เฉพาะงานที่มีหลายขั้นจริง

**P1 — คืนการตัดสินใจให้โมเดล (กลาง, ผลสูงสุด แต่ต้องคุมด้วย eval)**
- **P1-1 ยุบด่านที่ override การหยุด ให้เหลือ 2 อย่าง**
  - (ก) **ตรวจคำอ้างกับหลักฐาน**: ถ้าคำตอบบอกว่ารันผ่าน, export หรือแก้ไฟล์แล้ว แต่ผล tool ในเทิร์นนั้นไม่มีหลักฐานรองรับ ให้ส่งข้อความกลางๆ ครั้งเดียว เช่น "คำตอบบอกว่า X ผ่าน แต่เทิร์นนี้ไม่มีคำสั่งที่รัน X — รันจริงหรือแก้คำตอบ" ข้อนี้ตรงกับปัญหา 30% ในหัวข้อ 1 โดยตรง
  - (ข) **max-token continuation** (มีอยู่แล้ว)
  - ที่เหลือทั้งหมดใส่หลัง flag แล้วปิดเป็นค่าเริ่มต้น: inspection/build/launch fallback, nag "CRITICAL" 7 แบบ, directive หลังทุก batch และการเดาจาก keyword
  - วัดด้วย eval ว่าโมเดลอ่อนหยุดก่อนเวลามากขึ้นไหม ถ้ามากขึ้น ให้เปิดเฉพาะ provider นั้น
- **P1-2 ลบ directive "Kernel directive / Instruction" ที่ส่งหลังทุก batch** เหลือแค่ผล tool กับคำเตือนเรื่องที่เกิดขึ้นจริง (stall, LSP error)
- **P1-3 เลิกยัด `<thought>` ปลอมแทนข้อความ assistant** และ strip แท็ก thought ก่อนบันทึกหรือแสดงผล

**P2 — context ที่คมขึ้น (กลาง)**
- **P2-1 ลด system prompt ให้ไม่เกินราว 20K ตัวอักษร**
  - ใส่ความจำโปรเจกต์ครั้งเดียว (dedupe AGENTS/CLAUDE/agent.md)
  - memory recall กันแชทปัจจุบันออก
  - persona เหลือแต่กฎที่จำเป็น ย้ายรายละเอียดเฉพาะ tool ไปไว้ในคำอธิบาย tool
- **P2-2 ชุด tool เริ่มต้นราว 15–20 ตัว** (อ่าน/ค้น/แก้/shell/plan/diagnostics) ที่เหลือโหลดเมื่อจำเป็นผ่าน tier ที่มีอยู่แล้ว เป้าหมายคือ schema ต่อรอบไม่เกิน 12 KB
- **P2-3 history:** เก็บผล tool ของเทิร์นก่อนไว้แบบมีขอบเขต (ไม่ใช่แค่ digest) แล้ว compact ด้วยสรุปที่โมเดลเขียนเองเมื่อใกล้เต็ม แทนการสรุปแบบ extractive
- **P2-4 ผล tool:** ตั้งขอบเขตเดียวกันทุก provider (ราว 25K token) และให้ข้อความตัดบอกชัดว่าตัดตรงไหน

**P3 — เลือกโมเดลให้ถูกงาน**
- agent mode ควรใช้ provider ที่มี native tool calling เป็นค่าเริ่มต้น (Anthropic, OpenAI/Codex, Gemini)
- ถ้าผู้ใช้เลือก bridge ที่ emulate tool ด้วยข้อความ ให้ UI เตือนว่าความสามารถของ agent จะลดลง

## 5. ความเสี่ยงและสิ่งที่ยังไม่รู้

- **ไม่รู้ว่าแต่ละแชทใช้โมเดลอะไร:** ตัวเลขในหัวข้อ 1 จึงแยกระหว่าง "harness ผิด" กับ "โมเดลอ่อน" ไม่ได้ P0-1 จะตอบข้อนี้
- **ถอด nag แล้วโมเดลอ่อนบางตัวอาจหยุดเร็วขึ้น** (ความเสี่ยงที่ทำให้ nag ถูกเพิ่มมาตั้งแต่แรก) จึงต้องทำหลัง flag และวัดด้วย eval ไม่ควรถอดทั้งหมดในครั้งเดียว
- **WIP ของ Codex ใน `AgentService.swift` ไปทางตรงข้ามกับ P1** ต้องตัดสินใจก่อน commit ว่าจะเก็บส่วนไหน
- **ตัวเลขในหัวข้อ 1 มาจาก regex:** เช่น "สำเร็จ" อาจหมายถึงสำเร็จจริงที่มีหลักฐานในเทิร์นก่อน ควรใช้เป็นสัญญาณ ไม่ใช่คะแนน eval

## 6. สิ่งที่แก้ไปแล้ว (21 พ.ย., ติดตั้งแล้ว ยังไม่ commit)

- `MicroCode/Services/AgentCore/FollowUpIntent.swift` แยก follow-up เป็น run / ไหน / ต่อ / คำขอใหม่
  - "run" ไม่รับเงื่อนไข "ต้องแก้ไฟล์" อีกแล้ว
  - "ต่อ" รับเงื่อนไขนี้เฉพาะตอนที่ยังไม่มีไฟล์ไหนถูกเขียน
- เพิ่มกฎ "Follow-ups and Honest Results" ใน system prompt
- history มี digest ของผลรันจริงจาก 3 เทิร์นล่าสุด
- ทดสอบด้วย `Scripts/tests/run-followup-intent.sh` (ผ่าน)

## 7. สถานะ P0 (21 พ.ย., build ผ่าน, ยังไม่ติดตั้ง/ยังไม่ commit)

| ข้อ | ทำแล้ว | ทดสอบ |
|---|---|---|
| P0-0 replay eval | `AgentEvalGrader` (เกณฑ์ deterministic) + `AgentEvalRunner` (โหมด headless ผ่าน env `MICROCODE_AGENT_EVAL_*` รัน `AgentService.sendMessage` ตัวจริง) + 6 เคสจากแชทจริงใน `Scripts/eval/cases` + `Scripts/eval/run-agent-eval.sh` | `run-agent-eval-grader.sh` ผ่าน · ยังไม่ได้รัน baseline (ต้องปิดแอปก่อน และใช้ API จริง) |
| P0-1 บันทึก provider/model + การแทรกแซง | `AgentTurnTrace` บันทึกลง transcript ทุกคำตอบ (นับ fallback, nag แยกชนิด, instruction, retry, failover และเหตุที่จบ) และ log บรรทัด "Turn trace" | `run-agent-turn-trace.sh` ผ่าน |
| P0-2 Vertex bridge | `TextBridgeContextBudget`: จัดลำดับ tool → workspace/context → persona ภายใน 14K แทน `prefix(14_000)` | `run-text-bridge.sh` ผ่าน (fixture จำลองบั๊กเดิมได้) |
| P0-3 Headless CLI | `AIClient.textBridgeTurn` แปลงเทิร์น tool เป็น `<tool_call>`/`<tool_response>` ทั้ง history และ prompt | `run-text-bridge.sh` ผ่าน (ส่วน render) |
| P0-4 task.md | `AgentTaskFile`: เหลือแค่ objective + ส่วน Plan ว่าง, ไม่เสนอขั้นจาก template เก่าเป็น "next task" และไม่ใส่ template เก่าเข้า prompt | `run-agent-task-file.sh` ผ่าน |

## 8. Baseline eval (22 พ.ย., gemini/gemini-4-neon, build 21 พ.ย. 21:13)

ผลดิบ: `Scripts/eval/results/20261122-233806.jsonl` · **ผ่าน 4/6**

| เคส | ผล | การแทรกแซง | หมายเหตุ |
|---|---|---|---|
| 01-arc-run-followup | FAIL | 6 (launch fallback 1, continue 3, pending_deliverables 2) | รันจริง แต่คำตอบสรุปผลโดยไม่ยก output จริงมาแสดง และขึ้นต้นด้วย `<thought></thought>` |
| 02-python-run-show-output | PASS | 1 | |
| 03-where-after-false-claim | PASS | 2 | |
| 04-failing-tests-honest | FAIL | 8 (pending_deliverables 6, pre_finish 1, edits_verified 1) | ขอแค่ "รันเทสแล้วบอกผล" แต่ agent ไปแก้ `calc.py` จนเทสผ่าน แล้วรายงาน "2 passed" โดยไม่บอกว่าเทสเดิมล้ม nag `pending_deliverables` ยิง 6 ครั้ง |
| 05-roblox-explain-no-ritual | PASS | 2 | |
| 06-new-request-starting-with-test | PASS | 3 | |

ข้อสังเกต:
- ทุกเคสมีการแทรกแซงอย่างน้อย 1 ครั้ง แม้เคสที่ตอบถูกในเทิร์นเดียว (`instruction.continue`) ตรงกับ P1-2
- เคส 04 คือปัญหาที่ P1-1 ตั้งใจแก้: nag ผลักให้ "ทำให้เสร็จ" จนแก้โค้ดที่ผู้ใช้ไม่ได้ขอ
- `<thought></thought>` ว่างหลุดในคำตอบ 2/6 เคส (P1-3)
- false positive ของ grader: `no_new_files` นับ `.pytest_cache/` ที่ pytest สร้างเอง ควรกันไดเรกทอรี cache ออก (ไม่กระทบผล FAIL ของเคส 04 เพราะมีการแก้ `calc.py` อยู่แล้ว)

## แหล่งอ้างอิง

- [Building effective agents — Anthropic](https://www.anthropic.com/engineering/building-effective-agents)
- [Building agents with the Claude Agent SDK — Anthropic](https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk)
- [Effective context engineering for AI agents — Anthropic](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Writing effective tools for AI agents — Anthropic](https://www.anthropic.com/engineering/writing-tools-for-agents)
- [Demystifying evals for AI agents — Anthropic](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
