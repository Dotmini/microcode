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
    
    private let enabledKey = "microcode.enabledSkills.real.v2"
    
    init() {
        loadAndScanSkills()
    }
    
    func loadAndScanSkills() {
        isScanning = true
        var discovered: [AgentSkillItem] = []
        let fm = FileManager.default
        let home = NSHomeDirectory()
        
        let searchRoots = [
            "\(home)/.agents/skills",
            "\(home)/.codex/skills",
            "\(home)/.codex/plugins/cache",
            "\(home)/.gemini/config/skills",
            "\(home)/.gemini/config/plugins",
            "\(home)/.gemini/antigravity/builtin/skills"
        ]
        
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
    
    /// Returns the active instruction prompt of all enabled skills to inject into AgentService
    func activeSkillsPromptSnippet() -> String {
        let enabled = skills.filter { $0.isEnabled }
        guard !enabled.isEmpty else { return "" }
        
        var snippet = "\n\n## ACTIVE AGENT SKILLS & CAPABILITIES (\(enabled.count) Loaded):\n"
        for s in enabled {
            snippet += "### Skill: \(s.name) (`\(s.id)`)\n"
            snippet += "Path: \(s.filePath)\n"
            snippet += "\(s.description)\n\n"
        }
        snippet += "Before applying a skill, use file_read on its SKILL.md path and follow the complete instructions. A description is discovery metadata, not the skill itself.\n"
        return snippet
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
                    Text(skill.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
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
