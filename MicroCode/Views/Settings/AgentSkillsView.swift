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
    
    init() {
        loadAndScanSkills()
    }
    
    func loadAndScanSkills() {
        isScanning = true
        var discovered: [AgentSkillItem] = []
        let fm = FileManager.default
        let home = NSHomeDirectory()
        
        var searchRoots = [
            "\(home)/.microcode/skills",
            "\(home)/.agents/skills",
            "\(home)/.codex/skills",
            "\(home)/.codex/plugins/cache",
            "\(home)/.gemini/config/skills",
            "\(home)/.gemini/config/plugins",
            "\(home)/.gemini/antigravity/builtin/skills"
        ]
        
        // Scan active workspace and external volumes for project-specific skills
        if let ws = AgentToolBox.shared.workspaceRoot, !ws.isEmpty {
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
            ".git", ".build", "target", "node_modules", "DerivedData", "dist", "build"
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
        foundPaths = Array(Set(foundPaths)).sorted()
        
        let enabledSet = Set(UserDefaults.standard.stringArray(forKey: enabledKey) ?? [
            "antigravity-guide", "agy-customizations", "modern-web-guidance",
            "chrome-devtools", "bigquery-sql", "runpod-orchestrator",
            "dotmini-omni-ai", "alphafold_database_fetch_and_analyze", "pubmed_database",
            "accidental-data-loss-prevention"
        ])
        
        for path in foundPaths {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            
            // Extract skill name & description
            let url = URL(fileURLWithPath: path)
            let folderName = url.deletingLastPathComponent().lastPathComponent
            let skillId = folderName == "skills" ? url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent : folderName
            
            let (name, desc, category, tags) = parseSkillMeta(skillId: skillId, content: content, path: path)
            let (icon, color, provider) = categorizeSkillMeta(category: category, skillId: skillId, path: path)
            
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
                isEnabled: enabledSet.contains(skillId)
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
        UserDefaults.standard.set(enabled, forKey: enabledKey)
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
    
    /// Returns the active instruction prompt of matched & enabled skills to inject into AgentService.
    /// Automatically pre-injects full distilled instructions for Top-2 high-confidence JIT matches (Zero Extra Round-Trip).
    func activeSkillsPromptSnippet(
        forPrompt prompt: String = "",
        workspacePath: String? = nil,
        openFiles: [String] = []
    ) -> String {
        let ranked = rankSkills(forPrompt: prompt, workspacePath: workspacePath, openFiles: openFiles)
        guard !ranked.isEmpty else { return "" }
        
        // Top 2 high-confidence skills get Zero-Round-Trip JIT full instruction pre-loading
        let jitPreloaded = jitAutoRouterEnabled ? Array(ranked.filter { $0.score >= 24 }.prefix(2)) : []
        let jitIds = Set(jitPreloaded.map { $0.skill.id })
        if autoActivatedSkillIds != jitIds {
            autoActivatedSkillIds = jitIds
        }
        
        let catalogSkills = Array(ranked.filter { !jitIds.contains($0.skill.id) }.prefix(8))
        
        var snippet = "\n\n## MICROCODE AUTONOMOUS SKILL ENGINE (JIT Context-Aware Router)\n"
        snippet += "- Tool `skill_engine` is available (`recommend`, `activate`, `run_script`, `crystallize`).\n"
        
        if !jitPreloaded.isEmpty {
            snippet += "\n### ⚡ JIT AUTO-ACTIVATED SKILLS (Pre-Loaded — Execute Immediately Without Extra file_read):\n"
            for entry in jitPreloaded {
                let s = entry.skill
                let scripts = availableScripts(forSkill: s)
                snippet += "#### [JIT ACTIVE] \(s.name) (`\(s.id)`) — Match: \(entry.reason)\n"
                snippet += "- Path: `\(s.filePath)`\n"
                if !scripts.isEmpty {
                    snippet += "- Bundled Helper Scripts (run via `skill_engine(action: \"run_script\", skill_id: \"\(s.id)\", script: ...)`): `\(scripts.joined(separator: "`, `"))`\n"
                }
                snippet += "```markdown\n\(distilledInstructions(for: s, maxChars: 1400))\n```\n\n"
            }
        }
        
        if !catalogSkills.isEmpty {
            snippet += "### Active Skill Catalog (Use `skill_engine(action: \"activate\", skill_id: ...)` or `file_read` when needed):\n"
            for entry in catalogSkills {
                let s = entry.skill
                snippet += "- **`\(s.id)`** (\(s.name)): \(s.description.prefix(160)) [Path: `\(s.filePath)`]\n"
            }
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
        if scope.lowercased() == "global" {
            baseRoot = "\(NSHomeDirectory())/.microcode/skills"
        } else {
            let ws = workspacePath ?? AgentToolBox.shared.workspaceRoot ?? "\(NSHomeDirectory())/.microcode"
            baseRoot = (ws as NSString).appendingPathComponent(".microcode/skills")
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
