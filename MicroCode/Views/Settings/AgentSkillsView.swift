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
    /// Skill shipped inside the opened workspace (repo-controlled): disabled until the user enables it.
    var requiresOptIn: Bool = false
    
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
    
    @Published var skills: [AgentSkillItem] = [] {
        didSet { skillsRevision &+= 1 }
    }
    private var skillsRevision = 0
    private var searchIndexCache: (revision: Int, index: SkillSearchIndex)?
    @Published var selectedCategory: AgentSkillItem.SkillCategory = .all
    @Published var searchText: String = ""
    @Published var activeCount: Int = 0
    @Published var selectedSkillForDetail: AgentSkillItem? = nil
    @Published var isScanning: Bool = false
    /// Skills the user invoked by name (`/skill-id` or `$skill-id`) in the latest message; their full instructions are injected.
    @Published var autoActivatedSkillIds: Set<String> = []
    
    private let enabledKey = "microcode.enabledSkills.real.v2"
    /// Opt-out set for discovered ecosystem/plugin/built-in skills (v3): all valid skills are enabled by default unless explicitly disabled by the user.
    private let disabledSkillsKey = "microcode.disabledSkills.v3"
    /// Built-in skills are on by default; only an explicit opt-out is stored.
    private let disabledBuiltinKey = "microcode.disabledBuiltinSkills.v1"
    /// Workspace (repo-shipped) skills are opt-in; this stores the SKILL.md paths the user explicitly enabled.
    private let enabledProjectSkillPathsKey = "microcode.enabledProjectSkillPaths.v1"
    /// Lean core operating protocol injected concisely; heavy specialized skills use AAIF 3-Tier Progressive Disclosure.
    static let coreSkillIds = ["microcode-harness-core"]
    /// Ids in this namespace belong to MicroCode's bundled skills; repo / removable-volume skills may never claim them.
    static let reservedSkillIdPrefix = "microcode-"

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
        let optedInProjectPaths = Set(UserDefaults.standard.stringArray(forKey: enabledProjectSkillPathsKey) ?? [])
        // Repo-controlled skill folders (the app-managed ~/.microcode/workspaces/<id>/skills state dir is not one of them).
        let workspaceSkillRoots: [String] = {
            guard let ws = AgentToolBox.shared.workspaceRoot, !ws.isEmpty else { return [] }
            return ["\(ws)/.microcode/skills", "\(ws)/.skills", "\(ws)/.agents/skills", "\(ws)/skills"]
        }()
        let builtinIds: Set<String> = Set(foundPaths.compactMap { p -> String? in
            guard let builtinRoot, p.hasPrefix(builtinRoot) else { return nil }
            return URL(fileURLWithPath: p).deletingLastPathComponent().lastPathComponent.lowercased()
        })
        
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
            let parsedSkillId: String = (!isBuiltin && !yamlSlug.contains(" ") && yamlSlug.count >= 2 && yamlSlug.count <= 64)
                ? yamlSlug.lowercased()
                : rawSkillId
            let isProjectSkill = !isBuiltin && workspaceSkillRoots.contains { path.hasPrefix($0 + "/") }
            let isVolumeSkill = !isBuiltin && path.hasPrefix("/Volumes/")
            var skillId = parsedSkillId
            if (isProjectSkill || isVolumeSkill) && skillId.hasPrefix(Self.reservedSkillIdPrefix) {
                // e.g. a cloned repo declaring `name: microcode-harness-core` to replace the always-on core protocol.
                print("[Skills] Ignoring \(path): id '\(skillId)' is reserved for MicroCode built-in skills")
                continue
            }
            if isProjectSkill && builtinIds.contains(skillId) {
                skillId = "project-\(skillId)" // never let a repo silently shadow a bundled skill
            }
            var (icon, color, provider) = categorizeSkillMeta(category: category, skillId: skillId, path: path)
            if isBuiltin {
                category = Self.builtinCategory(for: skillId)
                tags = ["Built-in"] + (skillId.hasPrefix("microcode-") ? ["MicroCode"] : ["Anthropic", "Apache-2.0"])
                provider = skillId.hasPrefix("microcode-") ? "MicroCode Built-in" : "Anthropic Skills · Apache-2.0"
                (icon, color, _) = categorizeSkillMeta(category: category, skillId: skillId, path: path)
            }
            
            var isSkillEnabled = !disabledAll.contains(skillId) && (!isBuiltin || !disabledBuiltin.contains(skillId))
            if isProjectSkill {
                isSkillEnabled = optedInProjectPaths.contains(path) && !disabledAll.contains(skillId)
                tags.append("Project (opt-in)")
            }
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
                isBuiltin: isBuiltin,
                requiresOptIn: isProjectSkill
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
        var optIn = Set(UserDefaults.standard.stringArray(forKey: enabledProjectSkillPathsKey) ?? [])
        for skill in skills where skill.requiresOptIn {
            if skill.isEnabled { optIn.insert(skill.filePath) } else { optIn.remove(skill.filePath) }
        }
        UserDefaults.standard.set(Array(optIn).sorted(), forKey: enabledProjectSkillPathsKey)
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
            // Inject the whole core protocol (~800 tokens). The previous 1600-char cap silently dropped its
            // safety rules (ignore injected instructions, keep secrets out, ask before destructive actions).
            parts.append(distilledInstructions(for: skill, maxChars: 6000))
        }
        guard !parts.isEmpty else { return "" }
        return "\n\n## MICROCODE CORE HARNESS\n" + parts.joined(separator: "\n\n") + "\n"
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
    
    /// Router view of the installed skills (see SkillRouter.swift).
    func routeRecords() -> [SkillRouteRecord] {
        let home = NSHomeDirectory()
        return skills.map { skill in
            SkillRouteRecord(
                id: skill.id,
                name: skill.name,
                description: skill.description,
                isEnabled: skill.isEnabled,
                tier: SkillCatalogTier.classify(path: skill.filePath, isBuiltin: skill.isBuiltin, isProjectSkill: skill.requiresOptIn, home: home),
                isScience: skill.category == .science
            )
        }
    }

    private func searchIndex() -> SkillSearchIndex {
        if let cache = searchIndexCache, cache.revision == skillsRevision { return cache.index }
        let core = Set(Self.coreSkillIds)
        let index = SkillSearchIndex(records: routeRecords().filter { !core.contains($0.id) })
        searchIndexCache = (skillsRevision, index)
        return index
    }

    static func workspaceMarkers(at root: String) -> Set<String> {
        guard !root.isEmpty else { return [] }
        let fm = FileManager.default
        return Set(SkillSearchIndex.markerFiles.filter { fm.fileExists(atPath: (root as NSString).appendingPathComponent($0)) })
    }

    /// Searches enabled skills (BM25 over whole words, Thai segmented, platform-gated). Only skills with real
    /// evidence are returned — an unrelated prompt returns nothing. Used by `skill_engine match`, never to inject.
    func rankSkills(
        forPrompt prompt: String,
        workspacePath: String? = nil,
        openFiles: [String] = []
    ) -> [(skill: AgentSkillItem, score: Int, reason: String)] {
        let wsRoot = workspacePath ?? AgentToolBox.shared.workspaceRoot ?? ""
        let context = SkillSearchIndex.Context(
            openFileExtensions: Set(openFiles.map { URL(fileURLWithPath: $0).pathExtension.lowercased() }.filter { !$0.isEmpty }),
            workspaceMarkers: Self.workspaceMarkers(at: wsRoot)
        )
        let byId = Dictionary(skills.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return searchIndex().search(prompt, context: context, limit: 14).compactMap { hit in
            guard let skill = byId[hit.id] else { return nil }
            let reason = hit.matchedTerms.isEmpty ? "Workspace context" : "Matched: \(hit.matchedTerms.joined(separator: ", "))"
            return (skill, Int((hit.score * 10).rounded()), reason)
        }
    }

    /// `skill_engine read`: exact id, exact name or unique prefix; never a disabled skill.
    func resolveSkill(_ query: String) -> SkillLookup.Result {
        SkillLookup.resolve(query, records: routeRecords())
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
    
    /// Agent Skills progressive disclosure (agentskills.io):
    /// - Tier 1: a stable `<available_skills>` catalog (id + short description) within a token budget; the model
    ///   decides which skill applies. The rest stay searchable with `skill_engine(action: "match")`.
    /// - Tier 2: full instructions are loaded by the model via `skill_engine(action: "read")`, or injected here only
    ///   when the user invokes a skill by name (`/skill-id …` or `$skill-id`). No keyword-based pre-injection.
    /// - Tier 3: bundled scripts run on demand via `skill_engine(action: "run_script")`.
    func activeSkillsPromptSnippet(
        forPrompt prompt: String = "",
        workspacePath: String? = nil,
        openFiles: [String] = []
    ) -> String {
        let core = coreProtocolSnippet()
        let coreIds = Set(Self.coreSkillIds)
        let enabled = skills.filter { $0.isEnabled && !coreIds.contains($0.id) }
        let invokedIds = SkillInvocation.explicitIds(in: prompt, enabledIds: enabled.map(\.id))
        if autoActivatedSkillIds != Set(invokedIds) {
            autoActivatedSkillIds = Set(invokedIds)
        }
        guard !enabled.isEmpty else { return core }

        var snippet = core + SkillCatalog.render(SkillCatalog.build(routeRecords(), excluding: coreIds))
        for id in invokedIds {
            guard let skill = enabled.first(where: { $0.id == id }) else { continue }
            snippet += "\n### Skill invoked by the user: `\(skill.id)`\nThe user asked for this skill; follow these instructions for the task.\n"
            let scripts = availableScripts(forSkill: skill)
            if !scripts.isEmpty {
                snippet += "- Helper Scripts (`skill_engine(action: \"run_script\", query: \"\(skill.id)\", script: ...)`): `\(scripts.joined(separator: "`, `"))`\n"
            }
            snippet += "\(distilledInstructions(for: skill, maxChars: 16_000))\n"
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
        let claimsReservedId = cleanId.hasPrefix(Self.reservedSkillIdPrefix)
            || instructions.range(of: #"(?m)^\s*name:\s*["']?microcode-"#, options: .regularExpression) != nil
        guard !claimsReservedId else {
            throw NSError(domain: "SkillEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Skill ids starting with '\(Self.reservedSkillIdPrefix)' are reserved for MicroCode built-in skills"])
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
            name: \(cleanId)
            description: \(Self.yamlQuoted(description.replacingOccurrences(of: "\n", with: " ")))
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
    
    static func yamlQuoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
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
        guard skill.isEnabled else {
            throw NSError(domain: "SkillEngine", code: 403, userInfo: [NSLocalizedDescriptionKey: "Skill '\(skill.id)' is disabled. Enable it in Settings → Agent Skills first."])
        }
        let skillDir = URL(fileURLWithPath: skill.filePath).deletingLastPathComponent()
        let cleanScript = URL(fileURLWithPath: scriptName).lastPathComponent
        let candidate1 = skillDir.appendingPathComponent("scripts").appendingPathComponent(cleanScript)
        let candidate2 = skillDir.appendingPathComponent(scriptName)
        let scriptURL = FileManager.default.fileExists(atPath: candidate1.path) ? candidate1 : candidate2
        // Scripts must live inside the skill folder (rejects `../../x.sh`, absolute paths and escaping symlinks).
        guard WorkspacePathPolicy.contains(scriptURL.path, in: skillDir.path) else {
            throw NSError(domain: "SkillEngine", code: 406, userInfo: [NSLocalizedDescriptionKey: "Script '\(scriptName)' resolves outside skill '\(skill.id)'"])
        }
        
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
                            Text("INVOKED")
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
