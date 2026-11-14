//
//  AgentSkillsView.swift
//  MicroCode
//
//  Real-Time Agent Skills Hub & Execution Engine
//  Dynamically discovered and loaded from live filesystem:
//  ~/.gemini/config/skills • ~/.gemini/config/plugins • ~/.gemini/antigravity/builtin/skills
//

import SwiftUI

struct AgentSkillItem: Identifiable, Hashable {
    let id: String
    let name: String
    let category: SkillCategory
    let icon: String
    let color: Color
    let provider: String
    let description: String
    let filePath: String
    let instructions: String
    let tags: [String]
    var isEnabled: Bool
    var isBuiltin: Bool = false
    
    enum SkillCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case antigravity = "Antigravity"
        case coding = "Coding & Web"
        case cloudData = "Cloud & Data"
        case science = "Science & Bio"
        case engineering = "Engineering & MCP"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .all: return "sparkles"
            case .antigravity: return "atom"
            case .coding: return "curlybraces"
            case .cloudData: return "cloud.fill"
            case .science: return "waveform.path.ecg"
            case .engineering: return "terminal.fill"
            }
        }
    }
}

@MainActor
final class AgentSkillsStore: ObservableObject {
    static let shared = AgentSkillsStore()
    
    @Published var skills: [AgentSkillItem] = []
    @Published var selectedCategory: AgentSkillItem.SkillCategory = .all
    @Published var searchText: String = ""
    @Published var activeCount: Int = 0
    @Published var selectedSkillForDetail: AgentSkillItem? = nil
    @Published var isScanning: Bool = false
    @Published var autoActivatedSkillIds: Set<String> = []
    @Published var jitAutoRouterEnabled: Bool = true
    
    private let enabledKey = "microcode.enabledSkills.real.v2"
    /// Opt-out set for discovered ecosystem/plugin/built-in skills (v3): all valid skills are enabled by default unless explicitly disabled by the user.
    private let disabledSkillsKey = "microcode.disabledSkills.v3"
    /// Built-in skills are on by default; only an explicit opt-out is stored.
    private let disabledBuiltinKey = "microcode.disabledBuiltinSkills.v1"
    /// Lean core operating protocol injected concisely; heavy specialized skills use AAIF 3-Tier Progressive Disclosure.
    static let coreSkillIds = ["microcode-harness-core"]

    static var builtinRootPath: String? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("BuiltinSkills"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url.path
    }
    
    init() {
        loadAndScanSkills()
    }
    
    func loadAndScanSkills() {
        isScanning = true
        var discovered: [AgentSkillItem] = []
        let fm = FileManager.default
        let home = NSHomeDirectory()
        
        let builtinRoot = Self.builtinRootPath
        var searchRoots = [
            "\(home)/.microcode/skills",
            "\(home)/.agents/skills",
            "\(home)/.claude/skills",
            "\(home)/.claude/plugins",
            "\(home)/.codex/skills",
            "\(home)/.codex/plugins/cache",
            "\(home)/.gemini/config/skills",
            "\(home)/.gemini/config/plugins",
            "\(home)/.gemini/antigravity/builtin/skills",
            "\(home)/Documents/dotminiid/skills",
            "\(home)/Documents/SX/codetunner-native/skills"
        ]
        
        if let builtinRoot { searchRoots.append(builtinRoot) }

        // Scan user custom skill directory explicitly
        let customUserSkillsDir = "\(home)/.microcode/skills"
        if !fm.fileExists(atPath: customUserSkillsDir) {
            try? fm.createDirectory(atPath: customUserSkillsDir, withIntermediateDirectories: true)
        }
        searchRoots.append(customUserSkillsDir)
        if let ws = AgentToolBox.shared.workspaceRoot, !ws.isEmpty {
            searchRoots.append(WorkspaceStoragePaths.managedStateFile(named: "skills", workspacePath: ws).path)
            searchRoots.append("\(ws)/.microcode/skills")
            searchRoots.append("\(ws)/.skills")
            searchRoots.append("\(ws)/.agents/skills")
            searchRoots.append("\(ws)/skills")
        }
        
        // Scan mounted External SSD volumes (e.g. /Volumes/MAC, /Volumes/MicroCodeBuild)
        if let volContents = try? fm.contentsOfDirectory(atPath: "/Volumes") {
            for vol in volContents where !vol.starts(with: ".") {
                let volPath = "/Volumes/\(vol)"
                if fm.fileExists(atPath: "\(volPath)/.agents/skills") {
                    searchRoots.append("\(volPath)/.agents/skills")
                }
                if fm.fileExists(atPath: "\(volPath)/skills") {
                    searchRoots.append("\(volPath)/skills")
                }
            }
        }
        
        var foundPaths: [String] = []
        let ignoredDirectoryNames: Set<String> = [
            ".git", ".build", "target", "node_modules", "DerivedData", "dist", "build", "inactive-skills"
        ]
        
        for root in searchRoots {
            if let enumerator = fm.enumerator(atPath: root) {
                while let element = enumerator.nextObject() as? String {
                    let component = URL(fileURLWithPath: element).lastPathComponent
                    if ignoredDirectoryNames.contains(component) {
                        enumerator.skipDescendants()
                        continue
                    }
                    if element.hasSuffix("SKILL.md") || element.hasSuffix("skill.md") {
                        let fullPath = "\(root)/\(element)"
                        foundPaths.append(fullPath)
                    }
                }
            }
        }
        // User and workspace skills are processed before bundled ones, so a skill with the same id overrides the built-in.
        foundPaths = Array(Set(foundPaths)).sorted { lhs, rhs in
            let lb = builtinRoot.map { lhs.hasPrefix($0) } ?? false
            let rb = builtinRoot.map { rhs.hasPrefix($0) } ?? false
            if lb != rb { return !lb }
            return lhs < rhs
        }
        let disabledBuiltin = Set(UserDefaults.standard.stringArray(forKey: disabledBuiltinKey) ?? [])
        let disabledAll = Set(UserDefaults.standard.stringArray(forKey: disabledSkillsKey) ?? [])
        
        for path in foundPaths {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            
            // Extract skill name & description
            let url = URL(fileURLWithPath: path)
            let folderName = url.deletingLastPathComponent().lastPathComponent
            let parentName = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            let grandParentName = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            var rawSkillId = folderName == "skills" ? parentName : folderName
            if parentName == "skills" && !grandParentName.isEmpty && grandParentName != "config" && grandParentName != "builtin" && !rawSkillId.lowercased().hasPrefix(grandParentName.lowercased()) {
                rawSkillId = "\(grandParentName)-\(rawSkillId)"
            }
            
            let isBuiltin = builtinRoot.map { path.hasPrefix($0) } ?? false
            var (name, desc, category, tags) = parseSkillMeta(skillId: rawSkillId, content: content, path: path)
            let yamlSlug = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let skillId: String = (!isBuiltin && !yamlSlug.contains(" ") && yamlSlug.count >= 2 && yamlSlug.count <= 64)
                ? yamlSlug.lowercased()
                : rawSkillId
            var (icon, color, provider) = categorizeSkillMeta(category: category, skillId: skillId, path: path)
            if isBuiltin {
                category = Self.builtinCategory(for: skillId)
                tags = ["Built-in"] + (skillId.hasPrefix("microcode-") ? ["MicroCode"] : ["Anthropic", "Apache-2.0"])
                provider = skillId.hasPrefix("microcode-") ? "MicroCode Built-in" : "Anthropic Skills · Apache-2.0"
                (icon, color, _) = categorizeSkillMeta(category: category, skillId: skillId, path: path)
            }
            
            let isSkillEnabled = !disabledAll.contains(skillId) && (!isBuiltin || !disabledBuiltin.contains(skillId))
            let item = AgentSkillItem(
                id: skillId,
                name: name,
                category: category,
                icon: icon,
                color: color,
                provider: provider,
                description: desc,
                filePath: path,
                instructions: content,
                tags: tags,
                isEnabled: isSkillEnabled,
                isBuiltin: isBuiltin
            )
            
            if !discovered.contains(where: { $0.id == skillId }) {
                discovered.append(item)
            }
        }
        
        // Sort alphabetically by category then name
        discovered.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        
        skills = discovered
        updateCount()
        isScanning = false
    }
    
    private func parseSkillMeta(skillId: String, content: String, path: String) -> (name: String, desc: String, cat: AgentSkillItem.SkillCategory, tags: [String]) {
        var name = skillId.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
        var desc = ""
        var category: AgentSkillItem.SkillCategory = .engineering
        var tags: [String] = []
        
        let lines = content.components(separatedBy: .newlines)
        var inDescBlock = false
        var descLines: [String] = []
        
        for (i, line) in lines.prefix(50).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("name:") {
                inDescBlock = false
                name = trimmed.replacingOccurrences(of: "name:", with: "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
            } else if trimmed.hasPrefix("description:") {
                let val = trimmed.replacingOccurrences(of: "description:", with: "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                if val == "|" || val == ">-" || val == ">" || val.isEmpty {
                    inDescBlock = true
                } else {
                    desc = val
                    inDescBlock = false
                }
            } else if inDescBlock {
                if trimmed.hasPrefix("---") || (trimmed.contains(":") && !line.hasPrefix("  ") && !line.hasPrefix("\t")) {
                    inDescBlock = false
                } else if !trimmed.isEmpty && trimmed != "|" && trimmed != ">-" && trimmed != ">" {
                    descLines.append(trimmed)
                }
            } else if trimmed.hasPrefix("# ") && i < 5 {
                let heading = trimmed.replacingOccurrences(of: "# ", with: "").trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty && name == skillId.replacingOccurrences(of: "-", with: " ").capitalized {
                    name = heading
                }
            }
        }
        
        if desc.isEmpty && !descLines.isEmpty {
            desc = descLines.joined(separator: " ")
        }
        
        if desc.isEmpty || desc == "|" || desc == ">-" || desc == ">" {
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty && !t.starts(with: "#") && !t.starts(with: "---") && !t.starts(with: "```") && !t.starts(with: "name:") && !t.starts(with: "description:") && t != "|" && t != ">-" && t != ">" {
                    desc = t
                    break
                }
            }
        }
        
        if desc.isEmpty {
            desc = "Real agent skill loaded from \(URL(fileURLWithPath: path).lastPathComponent)"
        }
        
        // Categorize by keywords and path
        let lowPath = path.lowercased()
        let lowId = skillId.lowercased()
        
        if lowPath.contains("antigravity") || lowId.contains("antigravity") || lowId.contains("agy") || lowId.contains("loss-prevention") {
            category = .antigravity
            tags = ["Antigravity", "Core", "Autonomous"]
        } else if lowPath.contains("science") || lowId.contains("alpha") || lowId.contains("chem") || lowId.contains("bio") || lowId.contains("pdb") || lowId.contains("gene") || lowId.contains("variant") || lowId.contains("fold") || lowId.contains("mol") || lowId.contains("med") {
            category = .science
            tags = ["Science", "Bio", "Research"]
        } else if lowPath.contains("chrome") || lowPath.contains("web") || lowPath.contains("flutter") || lowPath.contains("dart") || lowId.contains("xcode") || lowId.contains("leak") || lowId.contains("css") || lowId.contains("json") {
            category = .coding
            tags = ["Coding", "Web", "DevTools"]
        } else if lowPath.contains("bigquery") || lowPath.contains("data") || lowPath.contains("spark") || lowPath.contains("airflow") || lowPath.contains("dbt") || lowPath.contains("gcs") || lowPath.contains("catalog") {
            category = .cloudData
            tags = ["Cloud", "BigQuery", "Data"]
        } else {
            category = .engineering
            tags = ["Tools", "Engineering", "MCP"]
        }
        
        return (name, desc, category, tags)
    }
    
    private func categorizeSkillMeta(category: AgentSkillItem.SkillCategory, skillId: String, path: String) -> (icon: String, color: Color, provider: String) {
        switch category {
        case .antigravity:
            return ("atom", Color(nsColor: .secondaryLabelColor), "Google Antigravity")
        case .coding:
            return ("curlybraces", Color(nsColor: .secondaryLabelColor), "Codex / Web Standards")
        case .cloudData:
            return ("cylinder.split.1x2.fill", Color(nsColor: .secondaryLabelColor), "Google Cloud Platform")
        case .science:
            return ("waveform.path.ecg.rectangle.fill", Color(nsColor: .secondaryLabelColor), "EMBL-EBI / DeepMind Science")
        case .engineering:
            return ("terminal.fill", Color(nsColor: .secondaryLabelColor), "Dotmini / MCP Engine")
        case .all:
            return ("sparkles", Color(nsColor: .secondaryLabelColor), "Unified AI")
        }
    }
    
    func toggleSkill(_ id: String) {
        if let idx = skills.firstIndex(where: { $0.id == id }) {
            skills[idx].isEnabled.toggle()
            saveEnabled()
            updateCount()
        }
    }
    
    func enableAll() {
        for idx in skills.indices {
            skills[idx].isEnabled = true
        }
        saveEnabled()
        updateCount()
    }
    
    func disableAll() {
        for idx in skills.indices {
            skills[idx].isEnabled = false
        }
        saveEnabled()
        updateCount()
    }
    
    private func updateCount() {
        activeCount = skills.filter { $0.isEnabled }.count
    }
    
    private func saveEnabled() {
        let enabled = skills.filter { $0.isEnabled }.map { $0.id }
        let disabled = skills.filter { !$0.isEnabled }.map { $0.id }
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        UserDefaults.standard.set(disabled, forKey: disabledSkillsKey)
        UserDefaults.standard.set(skills.filter { $0.isBuiltin && !$0.isEnabled }.map { $0.id }, forKey: disabledBuiltinKey)
    }
    
    func enabledSkillIds() -> [String] {
        skills.filter { $0.isEnabled }.map { $0.id }
    }
    
    func restoreSkills(_ skillIds: [String]) {
        let set = Set(skillIds)
        for idx in skills.indices {
            skills[idx].isEnabled = set.contains(skills[idx].id)
        }
        saveEnabled()
        updateCount()
    }
    
    private static func builtinCategory(for id: String) -> AgentSkillItem.SkillCategory {
        switch id {
        case "frontend-design", "webapp-testing", "theme-factory",
             "microcode-anti-slop", "microcode-swift-macos-ui", "microcode-thai-ui-typography":
            return .coding
        default:
            return .engineering
        }
    }

    /// Lean always-on operating baseline (kept compact so it never pollutes context or fights user intent).
    func coreProtocolSnippet() -> String {
        var parts: [String] = []
        for id in Self.coreSkillIds {
            guard let skill = skills.first(where: { $0.id == id && $0.isEnabled }) else { continue }
            parts.append(distilledInstructions(for: skill, maxChars: 1600))
        }
        guard !parts.isEmpty else { return "" }
        return "\n\n## MICROCODE CORE HARNESS\n" + parts.joined(separator: "\n\n") + "\n"
    }

    /// Intent-based boost for bundled skills; keyword lists are deliberately specific so a skill is not injected on unrelated turns.
    private static func builtinAffinity(id: String, prompt: String, openExts: Set<String>) -> (Int, String)? {
        func has(_ words: [String]) -> Bool { words.contains { prompt.contains($0) } }
        let hasThai = prompt.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) }
        switch id {
        case "frontend-design":
            if has(["landing page", "website", "web page", "webpage", "frontend", "front-end", "redesign", "หน้าเว็บ", "ออกแบบเว็บ"]) ||
                !openExts.isDisjoint(with: ["html", "css", "scss", "tsx", "jsx", "vue", "svelte"]) { return (34, "UI / frontend design task") }
        case "microcode-anti-slop":
            if has(["landing page", "copywriting", "anti-slop", "no slop", "เขียนบทความ", "หน้าเว็บ"]) { return (28, "Anti-slop quality guard") }
        case "theme-factory":
            if has(["theme", "palette", "slides", "deck", "color scheme", "colour scheme", "ธีม", "โทนสี", "ชุดสี"]) { return (30, "Theme / palette task") }
        case "microcode-swift-macos-ui":
            if has(["swiftui", "appkit", "macos", "nsview", "nswindow", "xcode", "toolbar", "sidebar", "swift "]) || openExts.contains("swift") { return (30, "Swift / macOS UI") }
        case "microcode-thai-ui-typography":
            let explicit = has(["thai", "ภาษาไทย", "th_th", "th-th", "localiz", "i18n", "พ.ศ."])
            let textIntent = has(["ui", "form", "report", "label", "copy", "font", "text", "document", "pdf", "translate", "แปล", "ฟอนต์", "ตัวอักษร", "ฟอร์ม", "รายงาน", "เอกสาร", "ข้อความ", "ปุ่ม"])
            if explicit || (hasThai && textIntent) { return (36, "Thai text / UI") }
        case "microcode-security-baseline":
            if has(["security", "secure", "auth", "token", "secret", "password", "vulnerab", "injection", "xss", "csrf", "encrypt", "keychain", "oauth", "credential", "ช่องโหว่", "ความปลอดภัย", "รหัสผ่าน"]) { return (32, "Security-sensitive change") }
        case "mcp-builder":
            // ONLY trigger mcp-builder when the user asks to BUILD/WRITE/IMPLEMENT an MCP server in code — NEVER when connecting/using an existing MCP like Canva!
            let isConnectingExistingMCP = has(["เชื่อม", "ต่อ mcp", "connect", "install", "login", "enable", "canva", "figma", "github", "gmail", "notion", "supabase"])
            let isBuildingNewMCPServer = has(["build mcp", "create mcp", "write mcp", "develop mcp", "fastmcp", "mcp sdk", "สร้าง mcp server", "เขียน mcp", "พัฒนา mcp"])
            if isBuildingNewMCPServer && !isConnectingExistingMCP { return (48, "Authoring new MCP server") }
        case "webapp-testing":
            if has(["playwright", "e2e", "browser test", "web app test", "ทดสอบเว็บ"]) { return (38, "Web app testing") }
        case "microcode-skill-authoring":
            if has(["skill.md", "crystalliz", "write a skill", "create a skill", "new skill", "สร้าง skill"]) { return (44, "Skill authoring") }
        default: break
        }
        return nil
    }

    // MARK: - Zero-Round-Trip Semantic JIT Skill Router & Autonomous Crystallizer
    
    func availableScripts(forSkill skill: AgentSkillItem) -> [String] {
        let skillDir = URL(fileURLWithPath: skill.filePath).deletingLastPathComponent()
        let scriptsDir = skillDir.appendingPathComponent("scripts")
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: scriptsDir.path) else {
            return []
        }
        return items.filter { !$0.hasPrefix(".") }.sorted()
    }
    
    /// Ranks all discovered skills against user prompt intent, workspace stack, and open editor files.
    func rankSkills(
        forPrompt prompt: String,
        workspacePath: String? = nil,
        openFiles: [String] = []
    ) -> [(skill: AgentSkillItem, score: Int, reason: String)] {
        let lowPrompt = prompt.lowercased()
        let promptTokens = Set(
            lowPrompt.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
        )
        let wsRoot = workspacePath ?? AgentToolBox.shared.workspaceRoot ?? ""
        let fm = FileManager.default
        
        // Workspace stack signals
        let hasPackageJson = !wsRoot.isEmpty && fm.fileExists(atPath: (wsRoot as NSString).appendingPathComponent("package.json"))
        let hasPubspec = !wsRoot.isEmpty && fm.fileExists(atPath: (wsRoot as NSString).appendingPathComponent("pubspec.yaml"))
        let hasFirebaseJson = !wsRoot.isEmpty && fm.fileExists(atPath: (wsRoot as NSString).appendingPathComponent("firebase.json"))
        let openExts = Set(openFiles.map { URL(fileURLWithPath: $0).pathExtension.lowercased() })
        
        var ranked: [(skill: AgentSkillItem, score: Int, reason: String)] = []
        
        for skill in skills {
            var score = skill.isEnabled ? 10 : 0
            var reasons: [String] = []
            let lowId = skill.id.lowercased()
            let lowName = skill.name.lowercased()
            let lowDesc = skill.description.lowercased()
            
            // 1. Direct ID or Name match in prompt
            if !lowPrompt.isEmpty && (lowPrompt.contains(lowId) || lowPrompt.contains(lowName)) {
                score += 55
                reasons.append("Direct prompt mention")
            }
            
            // 2. Keyword overlap between prompt tokens and skill ID/name/tags/description
            let idTokens = Set(lowId.components(separatedBy: CharacterSet(charactersIn: "-_.")).filter { $0.count >= 3 })
            let matchedIdTokens = promptTokens.intersection(idTokens)
            if !matchedIdTokens.isEmpty {
                score += matchedIdTokens.count * 18
                reasons.append("Matched keywords: \(matchedIdTokens.sorted().joined(separator: ", "))")
            }
            
            for token in promptTokens where token.count >= 4 {
                if lowDesc.contains(token) {
                    score += 6
                }
            }
            
            // 3. Workspace & file extension stack affinity
            if (openExts.contains("ar") || lowPrompt.contains("ardium")) && lowId.contains("ardium") {
                score += 45
                reasons.append("Ardium (.ar) context")
            }
            if (hasPubspec || openExts.contains("dart") || lowPrompt.contains("flutter")) && (lowId.contains("flutter") || lowId.contains("dart")) {
                score += 30
                reasons.append("Flutter/Dart project")
            }
            if (hasFirebaseJson || lowPrompt.contains("firebase") || lowPrompt.contains("firestore")) && (lowId.contains("firebase") || lowId.contains("firestore")) {
                score += 32
                reasons.append("Firebase workspace")
            }
            if hasPackageJson && (lowPrompt.contains("lcp") || lowPrompt.contains("devtools") || lowPrompt.contains("a11y") || lowPrompt.contains("memory leak")) {
                if ["chrome-devtools", "debug-optimize-lcp", "a11y-debugging", "memory-leak-debugging"].contains(lowId) {
                    score += 35
                    reasons.append("Web diagnostics match")
                }
            }
            if (lowPrompt.contains("simulator") || lowPrompt.contains("emulator") || lowPrompt.contains("adb") || lowPrompt.contains("android") || lowPrompt.contains("ios")) &&
               ["device-automation", "android-cli", "mobile-release-automation", "xcode-project-setup"].contains(lowId) {
                score += 38
                reasons.append("Mobile device/runtime task")
            }
            if (openExts.contains("pdb") || openExts.contains("cif") || openExts.contains("mmcif") || lowPrompt.contains("protein") || lowPrompt.contains("alphafold") || lowPrompt.contains("uniprot")) &&
               skill.category == .science {
                score += 35
                reasons.append("Biomolecular/Science task")
            }
            if (lowPrompt.contains("runpod") || lowPrompt.contains("gpu")) && lowId == "runpod-orchestrator" {
                score += 45
                reasons.append("RunPod GPU orchestration")
            }
            if (lowPrompt.contains("omni") || lowPrompt.contains("o1x") || lowPrompt.contains("tpat")) && lowId == "dotmini-omni-ai" {
                score += 45
                reasons.append("Dotmini Omni AI")
            }
            
            if skill.isBuiltin, let boost = Self.builtinAffinity(id: lowId, prompt: lowPrompt, openExts: openExts) {
                score += boost.0
                reasons.append(boost.1)
            }
            
            if score > 0 {
                ranked.append((skill, score, reasons.isEmpty ? "User enabled" : reasons.joined(separator: " • ")))
            }
        }
        
        return ranked.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.skill.name < $1.skill.name
        }
    }
    
    /// Distills the actionable core of a SKILL.md (stripping YAML frontmatter) for Zero-Round-Trip JIT injection
    func distilledInstructions(for skill: AgentSkillItem, maxChars: Int = 1500) -> String {
        var body = skill.instructions
        if body.hasPrefix("---") {
            let parts = body.components(separatedBy: "---")
            if parts.count >= 3 {
                body = parts.dropFirst(2).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if body.count <= maxChars { return body }
        return String(body.prefix(maxChars)) + "\n... [Full skill at \(skill.filePath)]"
    }
    
    /// AAIF 3-Tier Progressive Disclosure Skill Router:
    /// - Tier 1 (Always lightweight): Injects a compact `<available_skills>` table-of-contents (ID + 1-line description + path)
    ///   for the top relevant enabled skills (~40 tokens/skill, zero prompt bloat).
    /// - Tier 2 (On-Demand Activation): The LLM reads full `SKILL.md` via `skill_engine(action: "read", query: "<id>")` or `file_read`
    ///   ONLY when user intent genuinely requires that skill (plus at most 1 ultra-high-precision match `score >= 58` pre-warmed).
    /// - Tier 3 (Executable Resources): Bundled `scripts/` and `references/` are invoked on demand via `skill_engine(action: "run_script")`.
    func activeSkillsPromptSnippet(
        forPrompt prompt: String = "",
        workspacePath: String? = nil,
        openFiles: [String] = []
    ) -> String {
        let core = coreProtocolSnippet()
        let coreIds = Set(Self.coreSkillIds)
        let ranked = rankSkills(forPrompt: prompt, workspacePath: workspacePath, openFiles: openFiles)
            .filter { $0.skill.isEnabled && !coreIds.contains($0.skill.id) }
        guard !ranked.isEmpty else { return core }
        
        // Only pre-warm 1 unambiguous exact-intent skill (score >= 58); everything else uses Progressive Disclosure!
        let jitPreloaded = jitAutoRouterEnabled ? Array(ranked.filter { $0.score >= 58 }.prefix(1)) : []
        let jitIds = Set(jitPreloaded.map { $0.skill.id })
        if autoActivatedSkillIds != jitIds {
            autoActivatedSkillIds = jitIds
        }
        
        let catalogSkills = Array(ranked.filter { !jitIds.contains($0.skill.id) }.prefix(14))
        
        var snippet = core + "\n\n## AVAILABLE AGENT SKILLS (Progressive Disclosure)\n"
        snippet += "- If a listed skill clearly applies to the user's request, MUST read its `SKILL.md` instructions first via `skill_engine(action: \"read\", query: \"<skill_id>\")` or `file_read` before executing.\n"
        snippet += "- Do NOT activate unrelated skills. You can also search all \(skills.count) installed skills via `skill_engine(action: \"match\", query: \"...\")`.\n"
        
        if !jitPreloaded.isEmpty {
            for entry in jitPreloaded {
                let s = entry.skill
                let scripts = availableScripts(forSkill: s)
                snippet += "\n### Active Skill: `\(s.id)` (\(s.name)) — Path: `\(s.filePath)`\n"
                if !scripts.isEmpty {
                    snippet += "- Helper Scripts (`skill_engine(action: \"run_script\", query: \"\(s.id)\", script: ...)`): `\(scripts.joined(separator: "`, `"))`\n"
                }
                snippet += "\(distilledInstructions(for: s, maxChars: 1100))\n"
            }
        }
        
        if !catalogSkills.isEmpty {
            snippet += "\n<available_skills>\n"
            for entry in catalogSkills {
                let s = entry.skill
                let oneLineDesc = s.description.replacingOccurrences(of: "\n", with: " ").prefix(150)
                snippet += "- \(s.id) (\(s.filePath)): \(oneLineDesc)\n"
            }
            snippet += "</available_skills>\n"
        }
        
        return snippet
    }
    
    /// Autonomously crystallizes a reusable workflow, architecture pattern, or debugging recipe into a real SKILL.md on disk
    @discardableResult
    func crystallizeSkill(
        id rawId: String,
        name: String,
        description: String,
        instructions: String,
        scriptName: String? = nil,
        scriptContent: String? = nil,
        scope: String = "workspace",
        workspacePath: String? = nil
    ) throws -> AgentSkillItem {
        let cleanId = rawId.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-_]", with: "", options: .regularExpression)
        guard !cleanId.isEmpty else {
            throw NSError(domain: "SkillEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid skill_id"])
        }
        
        let baseRoot: String
        let userHome = FileManager.default.homeDirectoryForCurrentUser.path
        if scope.lowercased() == "global" {
            baseRoot = "\(userHome)/.microcode/skills"
        } else {
            let ws = workspacePath ?? AgentToolBox.shared.workspaceRoot
            baseRoot = WorkspaceStoragePaths.managedStateFile(named: "skills", workspacePath: ws).path
        }
        
        let skillDir = URL(fileURLWithPath: baseRoot).appendingPathComponent(cleanId)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        
        let skillFile = skillDir.appendingPathComponent("SKILL.md")
        let finalMarkdown: String
        if instructions.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---") {
            finalMarkdown = instructions
        } else {
            finalMarkdown = """
            ---
            name: \(name)
            description: \(description.replacingOccurrences(of: "\n", with: " "))
            ---
            
            # \(name)
            
            \(instructions)
            """
        }
        try AgentPrivacyGuard.safeWrite(content: finalMarkdown, to: skillFile)
        
        if let sName = scriptName, !sName.isEmpty, let sCode = scriptContent, !sCode.isEmpty {
            let scriptsDir = skillDir.appendingPathComponent("scripts")
            try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
            let safeScriptName = URL(fileURLWithPath: sName).lastPathComponent
            let scriptURL = scriptsDir.appendingPathComponent(safeScriptName)
            try AgentPrivacyGuard.safeWrite(content: sCode, to: scriptURL)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        }
        
        var enabled = Set(UserDefaults.standard.stringArray(forKey: enabledKey) ?? [])
        enabled.insert(cleanId)
        UserDefaults.standard.set(Array(enabled), forKey: enabledKey)
        
        loadAndScanSkills()
        if let created = skills.first(where: { $0.id == cleanId }) {
            return created
        }
        throw NSError(domain: "SkillEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Skill written to \(skillFile.path) but not indexed"])
    }
    
    /// Executes a bundled helper script inside a skill's `scripts/` directory using MicroCode Portable Runtimes
    func executeSkillScript(
        skillId: String,
        scriptName: String,
        arguments: [String] = [],
        workspacePath: String? = nil
    ) async throws -> String {
        guard let skill = skills.first(where: { $0.id.lowercased() == skillId.lowercased() }) else {
            throw NSError(domain: "SkillEngine", code: 404, userInfo: [NSLocalizedDescriptionKey: "Skill '\(skillId)' not found"])
        }
        let skillDir = URL(fileURLWithPath: skill.filePath).deletingLastPathComponent()
        let cleanScript = URL(fileURLWithPath: scriptName).lastPathComponent
        let candidate1 = skillDir.appendingPathComponent("scripts").appendingPathComponent(cleanScript)
        let candidate2 = skillDir.appendingPathComponent(scriptName)
        let scriptURL = FileManager.default.fileExists(atPath: candidate1.path) ? candidate1 : candidate2
        
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            let available = availableScripts(forSkill: skill)
            throw NSError(
                domain: "SkillEngine",
                code: 405,
                userInfo: [NSLocalizedDescriptionKey: "Script '\(scriptName)' not found in \(skill.id). Available scripts: \(available.joined(separator: ", "))"]
            )
        }
        
        let ext = scriptURL.pathExtension.lowercased()
        let escapedArgs = arguments.map { $0.shellEscaped() }.joined(separator: " ")
        let cmd: String
        switch ext {
        case "py":
            cmd = "python3 \(scriptURL.path.shellEscaped()) \(escapedArgs)"
        case "js", "mjs":
            cmd = "node \(scriptURL.path.shellEscaped()) \(escapedArgs)"
        case "ts":
            cmd = "npx -y ts-node \(scriptURL.path.shellEscaped()) \(escapedArgs)"
        case "ar":
            cmd = "arc run \(scriptURL.path.shellEscaped()) \(escapedArgs)"
        default:
            cmd = "bash \(scriptURL.path.shellEscaped()) \(escapedArgs)"
        }
        
        let cwd = workspacePath ?? AgentToolBox.shared.workspaceRoot ?? skillDir.path
        return try await ShellCommandTool().execute(params: ["command": cmd, "cwd": cwd])
    }
}

struct AgentSkillsView: View {
    @StateObject private var store = AgentSkillsStore.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // ── Header Bar ──
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Agent Skills Engine")
                                .font(.system(size: 15, weight: .bold))
                            
                            Text("\(store.activeCount) / \(store.skills.count) Active")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        Text("Live-loaded real instruction toolkits from Antigravity, Codex, Science & MCP on disk")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button {
                        store.loadAndScanSkills()
                    } label: {
                        Label("Rescan Disk", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        let panel = NSOpenPanel()
                        panel.title = "Import Custom .skill or .md / Folder"
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = true
                        panel.allowedFileTypes = ["md", "skill", "zip"]
                        if panel.runModal() == .OK {
                            for url in panel.urls {
                                do {
                                    if url.hasDirectoryPath {
                                        let fm = FileManager.default
                                        let home = NSHomeDirectory()
                                        let targetDir = URL(fileURLWithPath: "\(home)/.microcode/skills/\(url.lastPathComponent)")
                                        if fm.fileExists(atPath: targetDir.path) { try fm.removeItem(at: targetDir) }
                                        try fm.copyItem(at: url, to: targetDir)
                                    } else {
                                       let content = try String(contentsOf: url, encoding: .utf8)
                                       let filename = url.lastPathComponent
                                       let cleanName = filename.hasSuffix(".md") ? String(filename.dropLast(3)) : (filename.hasSuffix(".skill") ? String(filename.dropLast(6)) : filename)
                                       let skillId = cleanName.lowercased().replacingOccurrences(of: " ", with: "-")
                                       let _ = try store.crystallizeSkill(id: skillId, name: cleanName, description: "Imported custom skill from \(filename)", instructions: content)
                                    }
                                } catch {
                                    print("Failed to import skill: \(error)")
                                }
                            }
                            store.loadAndScanSkills()
                        }
                    } label: {
                        Label("Import Skill / .md...", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button("Enable All") { store.enableAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    
                    Button("Disable All") { store.disableAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            
            // ── Filter Bar ──
            HStack(spacing: 12) {
                // Search Input
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Search real skills, instructions, keywords...", text: $store.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !store.searchText.isEmpty {
                        Button {
                            store.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                )
                
                // Category Selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(AgentSkillItem.SkillCategory.allCases) { cat in
                            Button {
                                store.selectedCategory = cat
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 10))
                                    Text(cat.rawValue)
                                        .font(.system(size: 11, weight: store.selectedCategory == cat ? .semibold : .regular))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(store.selectedCategory == cat ? Color.primary.opacity(0.12) : Color.primary.opacity(0.03))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(store.selectedCategory == cat ? Color.primary.opacity(0.18) : Color.clear, lineWidth: 1)
                                        )
                                )
                                .foregroundColor(store.selectedCategory == cat ? .primary : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            // ── Skills Grid ──
            let filtered = filteredSkills
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No skills match your search")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(filtered) { skill in
                        skillCard(skill)
                    }
                }
            }
        }
        .sheet(item: $store.selectedSkillForDetail) { item in
            skillDetailSheet(item)
        }
    }
    
    private var filteredSkills: [AgentSkillItem] {
        store.skills.filter { item in
            let matchesCategory = store.selectedCategory == .all || item.category == store.selectedCategory
            let matchesSearch = store.searchText.isEmpty ||
                item.name.localizedCaseInsensitiveContains(store.searchText) ||
                item.description.localizedCaseInsensitiveContains(store.searchText) ||
                item.provider.localizedCaseInsensitiveContains(store.searchText) ||
                item.filePath.localizedCaseInsensitiveContains(store.searchText) ||
                item.tags.contains { $0.localizedCaseInsensitiveContains(store.searchText) }
            return matchesCategory && matchesSearch
        }
    }
    
    @ViewBuilder
    private func skillCard(_ skill: AgentSkillItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: skill.icon)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(skill.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        if store.autoActivatedSkillIds.contains(skill.id) {
                            Text("JIT AUTO")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.teal)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.teal.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }
                    Text(skill.provider)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { skill.isEnabled },
                    set: { _ in store.toggleSkill(skill.id) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }
            
            Text(skill.description)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 4) {
                Button {
                    store.selectedSkillForDetail = skill
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9))
                        Text("View SKILL.md")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                ForEach(skill.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(3)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(skill.isEnabled ? skill.color.opacity(0.25) : Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
    }
    
    @ViewBuilder
    private func skillDetailSheet(_ skill: AgentSkillItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: skill.icon)
                        .font(.system(size: 16))
                        .foregroundColor(skill.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name)
                            .font(.system(size: 15, weight: .bold))
                        Text(skill.filePath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Close") {
                    store.selectedSkillForDetail = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(skill.instructions)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 500, idealHeight: 650)
    }
}
