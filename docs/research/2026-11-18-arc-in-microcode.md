# วิจัย: ใช้ภาษา Arc เขียน MicroCode ให้มากขึ้น และทำให้ runtime เป็นเวอร์ชันล่าสุดเสมอ

วันที่: 2026-11-18 · ขอบเขต: Arc 3.1.0 (`/Users/dotmini/Documents/ardium`, branch `arc-native-compiler`) และ MicroCode (branch `codex/agent-autonomy-fixes`)

**วิธีทำ:**
- สำรวจ 2 repo แบบอ่านอย่างเดียว ได้แก่ toolchain ของ Arc และส่วนที่ MicroCode เชื่อมกับ Ardium/Arc
- เปิดโค้ดและดิสก์ตรวจซ้ำเองทุกข้อที่ใช้ตัดสินใจ (✅ = ตรวจเองแล้ว)
- ไม่ได้ build หรือแก้ไฟล์ใน repo ทั้งสอง

## สรุป

1. **ยังเอา Arc ไปคอมไพล์รวมเข้า binary ของ MicroCode โดยตรงไม่ได้** (in-process ผ่าน C ABI แบบเดียวกับ Rust core)
   - Arc 3.1 สร้างได้แค่ executable และไม่มีทาง export ฟังก์ชันให้ Swift เรียก
   - runtime ใช้ state ระดับ process ที่รองรับแค่ thread เดียว และสั่ง `exit()` ทั้ง process เมื่อ panic
   - ทั้งหมดนี้เป็นงานฝั่ง repo ของ Arc (ROADMAP phase 3–4) ไม่ใช่ฝั่ง MicroCode
2. **สิ่งที่ทำได้ตั้งแต่วันนี้:**
   - (ก) แก้การเชื่อม Arc ใน MicroCode ให้ถูกต้องและอัปเดตอัตโนมัติ
   - (ข) เขียน helper เป็นโปรแกรม Arc แยก แล้วคุยกับแอปผ่าน JSON ทาง stdin/stdout
   - (ค) ใช้ Arc กับเครื่องมือพัฒนา (benchmark, script, test driver)
3. **ตอนนี้ runtime ไม่เคยอัปเดตเลย**
   - MicroCode ไม่มี updater หรือการเช็กเวอร์ชันใดๆ และมีโค้ดค้นหา toolchain อย่างน้อย 7 ชุดที่ทำงานไม่เหมือนกัน
   - เครื่องนี้มี Arc 3 ตัวพร้อมกัน: `arc` 3.1.0, `ardium` 2.3 และ `/usr/local/ardium` 2.2.0
   - agent จึงไปเจอ `ardium` 2.3 ผ่าน PATH และได้ parse error `Ardium.Parser.MenhirBasics` ซ้ำ 25 ครั้ง (2026-11-18)
4. **ฝั่ง Arc เองก็ยังไม่พร้อมให้เครื่องอื่นอัปเดตอัตโนมัติ**
   - tag `v3.1.0` ไม่อยู่ในประวัติของ HEAD ✅
   - workflow release ยัง build toolchain OCaml รุ่นเก่า (`dune build` + `create_dmg_installer.sh` ที่ตั้งค่าไว้ 2.7.1) ✅

## 1. ข้อเท็จจริงของ Arc 3.1

| เรื่อง | สถานะ | หลักฐาน |
|---|---|---|
| ผลลัพธ์ของการคอมไพล์ | แปลงเป็น C ไฟล์เดียว แล้วสั่ง `cc` สร้าง **executable เท่านั้น** ไม่มี `.a`/`.dylib`/`-c` ส่วน `--emit-c` ก็มี `int main` + `arc_runtime_init` เสมอ | ✅ `src/compiler/cgen.cpp:1744-1745`, `driver.cpp:298-323` |
| Export ให้ C/Swift เรียก | ไม่มี ฟังก์ชันที่ generate ออกมาเป็น `static` ทั้งหมด (`@export` อยู่ใน roadmap phase 4) | ✅ `cgen.cpp:246, 250` |
| เรียก C จาก Arc (`extern fn`) | มีแค่ในงานที่ยังไม่ commit ส่วนตัว `arc` 3.1.0 ที่ติดตั้งอยู่ตอบว่า "not supported by this compiler yet" | ✅ ทดสอบด้วย `arc check` |
| Runtime | state ระดับ process แบบ global ไม่มี thread/lock (`pthread`/`mutex`/`_Atomic` = 0) ต้องเรียก `arc_runtime_init` ก่อน และตั้ง handler ของ SIGSEGV/SIGBUS ให้ทั้ง process | ✅ `arc_rt.c:2956-2962` |
| เมื่อเกิด error | panic สั่ง `exit(101)` และ OOM สั่ง `exit(134)` ถ้ารันอยู่ในแอปจะทำให้ MicroCode ปิดทั้งแอป | ✅ `arc_rt.c:193, 207` |
| GC และหน่วยความจำข้ามขอบเขต | GC แบบ stop-the-world (หรือเลือกโหมด `--mm=arc`) ส่วน object ที่ host ถืออยู่ GC มองไม่เห็น และ `str` เป็น struct ของ runtime ไม่ใช่ `char*` | `arc_rt.c:97, 150, 862` |
| stdlib ที่เกี่ยวกับ helper | อ่าน stdin ทีละบรรทัดได้ (`ReadLine`) ✅ และอ่าน/เขียนไฟล์ได้ แต่ `std/json` ยังไม่ commit ✅ ไม่มี regex ไม่มี HTTP client และ `exec` ดึง output กลับมาไม่ได้ | `ast.h:150`, `arc_rt.c:2263` |
| เครื่องมือ | ไม่มี debug info (DWARF/`#line`) ไม่มี LSP (`arc lsp` ไม่มีจริง) diagnostics เป็นข้อความธรรมดาและหยุดที่ error แรก ไม่มี package manager | รายงานสำรวจ |
| การปล่อยรุ่น | remote `github.com/XevilA/ardium` และ CI ทำงานเมื่อมี tag `v*.*.*` แต่ build OCaml ตัวเก่า ทั้ง `make install` ที่ลงไว้ที่ `/usr/local/bin/arc` และ `~/.local/bin/arc` ที่ใช้อยู่จริง ไม่มี script ไหนเป็นตัวติดตั้ง | ✅ `.github/workflows/build_and_release.yml:93-103` |
| ความเข้ากันได้กับ v2 | ไฟล์ `.ar` ยังใช้ได้ แต่ syntax ของ v2 หลายส่วนใช้ไม่ได้แล้ว (CoreUI, `@owned`, `extern`, พารามิเตอร์ที่ไม่ระบุ type) และยังไม่มีคู่มือ migrate | รายงานสำรวจ |

## 2. MicroCode เชื่อม Arc อยู่อย่างไรในตอนนี้

| เรื่อง | สิ่งที่พบ | หลักฐาน |
|---|---|---|
| ตัวค้นหา binary หลัก | `ArdiumRunner.findBinary` ไล่หา `$ARDIUM_BIN` → `~/.cargo/bin/arc` → … → `/usr/local/bin/ardium` → `which arc` โดยไม่มี `~/.local/bin` และไม่เช็กเวอร์ชัน ตอนนี้ได้ v3.1 เพราะ `~/.cargo/bin/arc` เป็น symlink ไปที่ `~/.local/bin/arc` โดยบังเอิญ | ✅ `ArdiumRunner.swift:21-62` |
| env ของ v2 ที่ใส่ให้ทุกครั้ง | `DYLD_LIBRARY_PATH=/usr/local/ardium/lib`, `ARDIUM_STDLIB=/usr/local/ardium/stdlib` ถูกใส่ให้ v3.1 ด้วย | ✅ `ArdiumRunner.swift:154-156, 199-201` |
| อาจ deadlock | อ่าน pipe หลัง `waitUntilExit` ถ้า output ใหญ่จะค้าง และไม่มี timeout | ✅ `ArdiumRunner.swift:211-214` |
| ตัวค้นหาอื่นที่ทำงานไม่ตรงกัน | `ProjectManager` หา **`ar`** (ซึ่งคือ archiver ไม่ใช่ Arc) ✅ `ProjectManager.swift:837-849` · Embedded Studio หา `ardium`/`ardiumc` · `ComputeKernel` หา `ardium` · Rust `backend/src/runner.rs:913-943` · `mcp-server.py:424-442` · skill script เรียก `arc` ผ่าน PATH | รายงานสำรวจ |
| PATH ของ shell/terminal | ใส่ `/usr/local/bin` ไว้ก่อน `~/.local/bin` agent จึงเจอ `ardium` 2.3 | `AgentToolBox.swift:4477-4491`, `AuthenticTerminal.swift:246-262` |
| Updater | ไม่มีของ Arc เลย ส่วน runtime อื่นใช้ `RuntimeManager.getDownloadInfo` (pin เวอร์ชันได้ แต่ไม่มี checksum และไม่เช็กอัปเดต) | `RuntimeManager.swift:104-199, 708-799` |
| prompt และ skill | ทุกจุดยังเขียนว่า "Ardium v2.3" ไม่มีคำว่า Arc 3.1 เลย ส่วน `AgentService.swift:747` อ้างว่า Ardium อยู่ใน `~/.microcode/runtimes` ซึ่งไม่จริง ✅ (ในโฟลเดอร์นั้นมีแค่ `openthai-ocr-venv`) และ skill `ardium-lang` ก็เป็น v2.3 | ✅ |
| LSP | `arc lsp` ถูกเรียกตอนเปิดแอป แต่คำสั่งนี้ไม่มีจริง และ stdout ก็ไม่ได้ต่อเข้ากับ JSON-RPC | `AppState.swift:1752`, `ArdiumLSPService.swift:13-64` |
| แพตเทิร์นที่ใช้ต่อได้ | Rust `microcode_core` ทำเป็น staticlib + UniFFI + `MicrocodeCoreSupport` (header + modulemap) และ `AgentDesktopBridge` ใช้ dylib ผ่าน `dlopen` | `Package.swift`, `build.sh:298-323` |

## 3. ทางเลือกในการเอา Arc เข้า source ของ MicroCode

### ทาง A: in-process (static library + C ABI) ยังทำไม่ได้
ต้องรอให้ฝั่ง Arc มีครบทุกข้อต่อไปนี้ก่อน
1. output แบบ library ที่ไม่มี `main` (เช่น `arc build --lib` ที่ได้ `.a` + header)
2. `@export` ที่สร้างฟังก์ชัน C ABI แบบไม่ `static`
3. runtime ที่ฝังในแอปได้ คือไม่ `exit()` แต่คืน error ให้ caller และไม่ยึด signal handler ของ process
4. กติกาเรื่อง thread อย่างใดอย่างหนึ่ง: ใช้ได้แค่ thread เดียวที่กำหนดไว้ หรือทำ runtime ให้ thread-safe
5. API ให้ host ถือ object ได้ (root/pin) และ type ข้ามขอบเขตที่ชัดเจน (`char*`, buffer, ความเป็นเจ้าของ)
6. debug info (`#line` หรือ DWARF) เพื่อให้ crash report ของแอปอ่านออก

เมื่อพร้อมแล้ว เริ่มจากโมดูลเล็กที่บริสุทธิ์ (pure) และไม่อยู่ในเส้นทางที่ต้องเร็ว เช่น `SlopLint.swift` (244 บรรทัด) หรือ `Models/MicFormat.swift` (135) โดยต่อแบบเดียวกับ `MicrocodeCoreSupport`

### ทาง B: Arc helper แยก process ทำได้ทันที เหมาะกับงาน batch
- **รูปแบบ:** ship executable ที่เขียนด้วย Arc ไปใน `Contents/Helpers/` (sign ด้วย identity ของแอป) แล้วคุยด้วย JSON ทีละบรรทัดผ่าน stdin/stdout
- **ข้อดี:** ถ้า helper crash หรือ panic แอปไม่ล่ม ใช้ได้กับ Arc 3.1 ตามที่เป็นอยู่ และเครื่องผู้ใช้ไม่ต้องมี `cc` เพราะ build ไว้ล่วงหน้าแล้ว
- **ข้อจำกัด:** มีค่าเริ่ม process ราว 10–50 ms ต่อครั้ง (ประมาณการ ยังไม่ได้วัด) จึงไม่เหมาะกับงานที่ต้องตอบทันที เช่นตอนพิมพ์ ไฮไลต์ หรือ parse stream
- **ต้องมีก่อน:** commit `std/json` และใช้ helper แบบอยู่ยาว (รับหลาย request ต่อ process เดียว) เพื่อตัดค่าเริ่ม process
- **งานที่เหมาะ:**
  - สร้าง index ของ codebase แบบ BM25 (`CodebaseSearchTool.swift`, 571)
  - repo map (`RepoMapService.swift`, 694)
  - lint (`SlopLint.swift`)
  - parser ของ log/build output (`XcodeBuildParser.swift`, 132)
  - งานเหล่านี้เป็น batch และมีชุดทดสอบเทียบกับเวอร์ชัน Swift ได้

### ทาง C: dogfood ในเครื่องมือของโปรเจกต์ ความเสี่ยงต่ำสุด
- ย้าย `benchmarks/*.py` หรือ test driver บางตัวมาเขียนด้วย Arc
- ข้อดีคือได้ทดสอบภาษากับงานจริงโดยไม่กระทบผู้ใช้แอป

## 4. ทำให้ runtime เป็นเวอร์ชันล่าสุดเสมอ (ข้อเสนอ)

**ฝั่ง MicroCode: `ArcToolchainManager` ตัวเดียว ใช้แทนตัวค้นหาทั้ง 7 ชุด**
1. **ลำดับการค้นหา:**
   - toolchain ที่ MicroCode ติดตั้งไว้เอง (`~/Library/Application Support/MicroCode/Runtimes/arc/<version>`, ชี้ด้วย symlink `current`)
   - `$ARC_BIN`
   - `~/.local/bin/arc`
   - `arc` ใน PATH
2. **เช็กเวอร์ชัน:** ตรวจด้วย `arc --version` (ปัจจุบันตอบว่า `arc 3.1.0`) ถ้าต่ำกว่า 3.0 ห้ามใช้ ส่วน `ardium` 2.x ให้ใช้เฉพาะเมื่อผู้ใช้เลือกเองว่าต้องการโหมด legacy
3. **ใส่ toolchain ลง PATH ก่อน `/usr/local/bin`** ทั้งใน shell ของ agent, terminal และ Playground และเลิกใส่ env ของ v2 (`DYLD_LIBRARY_PATH`/`ARDIUM_*`) ให้ v3
4. **เช็กอัปเดต:** ตอนเปิดแอป ทุก 24 ชั่วโมง และเมื่อกด "Check now"
   - แหล่งที่ 1: GitHub Releases ของ `XevilA/ardium` (ต้องแก้ CI ฝั่ง Arc ก่อน ดูหัวข้อถัดไป)
   - แหล่งที่ 2 (เครื่อง dev): repo ในเครื่อง ถ้า `VERSION` หรือ HEAD เปลี่ยน ให้ build ด้วย `make` แล้วติดตั้ง
5. **ติดตั้งแบบปลอดภัย:**
   - ดาวน์โหลด → ตรวจ SHA-256 → แตกไฟล์ลงโฟลเดอร์ของเวอร์ชันนั้น → รัน `arc doctor` → สลับ `current` แบบ atomic
   - เก็บเวอร์ชันก่อนหน้าไว้ rollback และมีตัวเลือก pin เวอร์ชันใน Settings
6. **อัปเดต skill พร้อม runtime:** สร้าง skill `arc-lang` จาก `LANGUAGE_REFERENCE.md` ที่มากับ release นั้น ทำให้ skill ตรงกับเวอร์ชันที่ติดตั้งเสมอ และ description ควรมีคำว่า "Arc (formerly Ardium)", `arc`, `.ar` ซึ่งแก้ปัญหาที่ agent หา skill ไม่เจอเพราะคำว่า "Arc"
7. **แก้ prompt ของ agent:** เปลี่ยนเป็น "Arc 3.x (formerly Ardium), CLI `arc`, files `.ar`" และเก็บชื่อ tool `ardium_run` ไว้เพื่อความเข้ากันได้ แต่ให้รันผ่าน `ArcToolchainManager`
8. **ความเสถียร:** แก้การอ่าน pipe ให้อ่านไปพร้อมกับที่ process ทำงาน, เพิ่ม timeout และเลิกเรียก `arc lsp` จนกว่าคำสั่งนี้จะมีจริง

**ฝั่ง repo Arc: ต้องทำก่อนจึงจะอัปเดตอัตโนมัติได้**
1. tag release บน branch ที่ปล่อยจริง (ตอนนี้ `v3.1.0` ไม่อยู่ในประวัติของ HEAD)
2. แก้ workflow ให้ build compiler C++ ของ Arc 3 แทน OCaml และแนบ `arc-<version>-macos-arm64.tar.gz` + `SHA256SUMS` (+ `LANGUAGE_REFERENCE.md`)
3. มี `make install PREFIX=…` ที่ใช้งานได้จริง แทน dmg script ที่ยังตั้งเป็น 2.7.1
4. (ทางเลือก) ทำ `arc --version --json` และ diagnostics แบบ JSON เพื่อให้ MicroCode แสดง error ของ Arc ใน editor ได้

## 5. ลำดับที่แนะนำ

| ลำดับ | งาน | ขนาดโดยประมาณ | เปลี่ยนพฤติกรรม? |
|---|---|---|---|
| 1 | `ArcToolchainManager` + ตัวค้นหาตัวเดียว + แก้ PATH/env/pipe + prompt + skill `arc-lang` | 1–2 วัน | ใช่ (agent และ Playground จะใช้ `arc` 3.x เสมอ) |
| 2 | updater (รอฝั่ง Arc แก้ release ก่อน ระหว่างนั้นใช้โหมด build จาก repo ในเครื่องได้) | 1–2 วัน + งานฝั่ง Arc | ใช่ |
| 3 | Arc helper ตัวแรก (เช่น สร้าง index BM25) พร้อมเทียบผลและความเร็วกับ Swift | 2–4 วัน | ไม่ (มีกลไก fallback ไปใช้ Swift) |
| 4 | in-process (ทาง A) หลังจาก Arc มี library output + `@export` + runtime ที่ฝังได้ | ขึ้นกับ roadmap ของ Arc | — |

ตัวเลขขนาดงานเป็นการประมาณ ยังไม่ได้วัด

## 6. สิ่งที่ต้องตัดสินใจ
1. เริ่มจากลำดับที่ 1 (แก้การเชื่อม + toolchain ตัวเดียว) หรือไม่
2. แหล่งอัปเดตหลักจะเป็น GitHub Releases (ต้องแก้ CI ของ Arc) หรือ build จาก repo ในเครื่อง หรือใช้ทั้งสองแบบ
3. จะให้แก้ repo Arc ด้วยหรือไม่ (release workflow, tag, ทำ `@export` และ library output ตาม roadmap) เพราะเป็น repo แยก จึงยังไม่ได้แตะ
4. `ardium` 2.x ที่ `/usr/local/bin` และ `/usr/local/ardium` จะเก็บไว้เป็นโหมด legacy หรือเลิกใช้
