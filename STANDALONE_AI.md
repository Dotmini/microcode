# MicroCode AI — Standalone Edition Architecture & Developer Guide

เอกสารนี้อธิบายโครงสร้างทางเทคนิค จุดเชื่อมโยงในโค้ด และวิธีพัฒนาต่อยอดของ **MicroCode AI (Standalone Edition)** ซึ่งเป็นรุ่นแยกพิเศษที่มีเฉพาะ **AI Agent Mode** และ **Settings** โดยทำงานแยกอิสระจาก **MicroCode IDE** ตัวหลัก 100%

---

## 1. ภาพรวมการแยกตัวแอป (Isolation Overview)

| คุณสมบัติ | MicroCode (Full IDE ตัวหลัก) | MicroCode AI (Standalone Edition) |
| :--- | :--- | :--- |
| **ตำแหน่งแอป** | `/Applications/MicroCode.app` | `/Applications/MicroCode AI.app` |
| **ซอร์สโค้ดและ Git** | repo เดียวกัน (`Dotmini/microcode`) build ด้วย `./build_dev.sh` | repo เดียวกัน build ด้วย `./build_ai_standalone.sh` และปล่อย release พร้อมกันด้วย `package_ai_from_lite.sh` |
| **Bundle Identifier** | `com.dotmini.microcode` | `com.dotmini.microcode.ai` |
| **Info.plist Flag** | ไม่มี | `MicroCodeStandaloneAI = true` (`<true/>`) |
| **Local Rust Backend Port** | `127.0.0.1:3000` | `127.0.0.1:3001` |
| **โหมดเริ่มต้นและโหมดที่อนุญาต** | ทุกโหมด (`Code Editor`, `Agent`, `Notebook`, `Playground`, `Science`, `Browser`, `SSH`, `IoT`, `API`) | ล็อกเฉพาะ `.aiAgent` (`AI Agent Mode`) เท่านั้น |
| **แถบด้านซ้าย (Left Sidebar)** | `Workspaces`, `Conversations`, และ `Workspace Files` | เฉพาะ `Workspaces`, `Conversations` และปุ่ม `Settings` |
| **หน้าต่าง Settings (`⌘,`)** | แสดงครบทุกหมวดหมู่ของ IDE | แสดงเฉพาะหมวด AI Agent และระบบหลัก (`AI & Agent`, `General`, `Skills`, `MCP Servers`, `Tools`, `Team Collaboration`, `Connect with Phone`, `Account & License`, `About`) |

---

## 2. กลไกตรวจสอบรุ่น (`AppEdition`)

ตัวแปรกลางที่ใช้แยกพฤติกรรมระหว่างรุ่นเต็ม (Full IDE) กับรุ่น `MicroCode AI (Standalone)` อยู่ที่ **`AppEdition`** ในไฟล์ `MicroCode/MicroCodeApp.swift`:

```swift
enum AppEdition {
    static let isStandaloneAI: Bool = {
        if Bundle.main.bundleIdentifier == "com.dotmini.microcode.ai" {
            return true
        }
        if (Bundle.main.object(forInfoDictionaryKey: "MicroCodeStandaloneAI") as? Bool) == true {
            return true
        }
        let bundleName = Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
        if bundleName == "MicroCode AI" || bundleName == "MicroCodeAI" {
            return true
        }
        if ProcessInfo.processInfo.environment["MICROCODE_STANDALONE_AI"] == "1" {
            return true
        }
        if CommandLine.arguments.contains("--standalone-ai") {
            return true
        }
        return false
    }()

    static var displayName: String {
        isStandaloneAI ? "MicroCode AI" : "MicroCode"
    }
}
```

### วิธีเปิดโหมด Standalone AI ตอนพัฒนา
สามารถเปิดโหมด Standalone AI ได้ 3 วิธี:
1. รันผ่านแอป `/Applications/MicroCode AI.app` (ซึ่งมี `CFBundleIdentifier = com.dotmini.microcode.ai` และ `MicroCodeStandaloneAI = true` ใน `Info.plist`)
2. ส่ง Environment Variable ตอนรัน: `MICROCODE_STANDALONE_AI=1`
3. ส่ง CLI Argument ตอนรัน: `--standalone-ai`

---

## 3. จุดสำคัญในโค้ดที่ควบคุม Standalone Mode

### 3.1 การล็อกโหมด `.aiAgent` (`MicroCode/Models/AppState.swift`)
- **`editorMode`**: กำหนดค่าเริ่มต้นเป็น `.aiAgent` ทันทีเมื่อ `AppEdition.isStandaloneAI == true` และมี `didSet` ป้องกันไม่ให้สลับไปโหมดอื่น
- **`setEditorMode(_:)` / `switchToMode(_:)` / `toggleEditorMode(_:)`**: บังคับให้ใช้ `.aiAgent` เสมอในโหมด Standalone
- **`closeWorkspace()` / `showWelcomeScreen()`**: ป้องกันไม่ให้เด้งกลับไปหน้าเลือกโหมด IDE (`WelcomeScreen`)

### 3.2 การตัด UI ส่วน IDE ออก (`MicroCode/Views/ContentView.swift`)
- **`AgenticEditorWorkspace`**:
  - `shouldShowWelcome`: คืนค่า `false` เสมอในรุ่น Standalone เพื่อเข้าสู่หน้าแชท AI Agent ทันทีที่เปิดแอป
  - `surface`: เริ่มต้นที่ `.agent` เสมอ และแสดง `AIAgentView` เป็นพื้นที่หลักเพียงอย่างเดียว
  - `installFastShortcutMonitorIfNeeded()`: ปิดคีย์ลัด `⌃0`–`⌃9` สำหรับสลับโหมด IDE
- **`WorkspaceUnifiedHeaderBar` (แถบด้านบน 36pt)**:
  - ซ่อนปุ่มสลับโหมด `Agent | Code Editor | More Mode`
  - ซ่อนเมนูเครื่องมือ IDE `AgenticLayoutMenu` (`[...]`)
  - แสดงปุ่ม `Settings` (`gearshape`) ไว้ที่มุมขวาบนตลอดเวลาคู่กับปุ่มเปิด/ปิดแผง `Context & Preview Inspector`
- **`AgenticWorkspaceSidebar` (แถบซ้าย)**:
  - เปลี่ยนชื่อหัวแถบเป็น `MicroCode AI`
  - ซ่อนส่วน `WORKSPACE FILES` (`workspaceFilesSection`) เพื่อให้พื้นที่ทั้งหมดของ Sidebar แสดงรายการ **Workspaces & Conversations** ได้เต็มความสูง
  - ซ่อนเมนูคลิกขวา `"Open in Code Editor"`

### 3.3 การกรองหน้า Settings (`MicroCode/Views/Workspace/WorkspaceSettingsAndWindowModifiers.swift`)
- **`SettingsView.visibleSidebarItems`**:
  - ซ่อนหมวดเฉพาะของ IDE ได้แก่ `Editor` (`tab: 1`), `Cloud GPU` (`tab: 9`), และ `Extensions` (`tab: 5`)
  - คงไว้เฉพาะหมวดที่จำเป็นสำหรับ AI Agent:
    - `AI & Agent` (`tab: 2` — Cloud Subscription, BYOK 21+ ค่าย, ACP CLI Agents, Local LLM Multi-Endpoint)
    - `General` (`tab: 0` — Theme, Font, Language)
    - `Skills` (`tab: 10`), `MCP Servers` (`tab: 8`), `Tools` (`tab: 3`)
    - `Team Collaboration` (`tab: 12`), `Connect with Phone` (`tab: 11`)
    - `Account & License` (`tab: 6`), `About` (`tab: 4`)

### 3.4 การแยกพอร์ตและโปรเซส Backend (`MicroCode/Services/BackendService.swift`)
- **`BackendService.backendPort`**:
  - ใช้พอร์ต `3000` สำหรับ `MicroCode.app` (ตัวหลัก)
  - ใช้พอร์ต `3001` สำหรับ `MicroCode AI.app` (ตัวแยก) พร้อมส่ง `PORT=3001` และ `MICROCODE_PORT=3001` ให้โปรเซส `microcode-backend`
- **`killStaleBackends()`**:
  - ตรวจสอบและเคลียร์เฉพาะโปรเซสที่ถือพอร์ตของตัวเอง (`lsof -ti tcp:<port>`) เท่านั้น ไม่ใช้ `pkill -9 -x microcode-backend` แบบเหมาทั้งหมด ทำให้เปิด `MicroCode.app` และ `MicroCode AI.app` พร้อมกันได้โดยไม่กวนกัน

---

## 4. คำสั่ง Build และ Run

### คอมไพล์และอัปเดต `/Applications/MicroCode AI.app` (ไม่แตะตัวหลัก)
```bash
# คอมไพล์แบบ Incremental Debug (เร็วสุดสำหรับตอนพัฒนา)
./build_ai_standalone.sh

# คอมไพล์แบบ Release Optimization
./build_ai_standalone.sh --release
```

### รันแอปพลิเคชัน
```bash
open -n "/Applications/MicroCode AI.app"
```

---

## 5. แนวทางการพัฒนาต่อยอด (Future Customization)

หากต้องการเพิ่มฟีเจอร์เฉพาะของ **MicroCode AI** ในอนาคต:
1. **การแก้ไขเฉพาะรุ่น Standalone**: ใช้เงื่อนไข `if AppEdition.isStandaloneAI { ... }` ในจุดที่แชร์โค้ดร่วมกัน หรือพัฒนาแยกในโฟลเดอร์ `/Users/dotmini/Documents/SX/microcode-ai`
2. **การเปลี่ยนไอคอนเฉพาะของ `MicroCode AI.app`**: สามารถวางไฟล์ไอคอนชื่อ `AppIconAI.icns` แล้วแก้ใน `build_ai_standalone.sh` ให้คัดลอกทับ `Contents/Resources/AppIcon.icns` ของ `/Applications/MicroCode AI.app` ได้ทันที
3. **การสร้างไฟล์ติดตั้ง `.dmg` แยกสำหรับ MicroCode AI**:
   ```bash
   hdiutil create -volname "MicroCode AI" -srcfolder "/Applications/MicroCode AI.app" -ov -format UDZO "Dotmini_MicroCode_AI.dmg"
   ```
