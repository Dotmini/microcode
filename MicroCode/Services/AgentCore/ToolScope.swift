//
//  ToolScope.swift
//  MicroCode
//
//  Adaptive Tool Scoping Engine & Hybrid Orchestration Tiers.
//  Filters agent tools by task complexity, device preview state, and domain
//  to optimize token context window and eliminate prompt hallucination.
//  Tirawat Nantamas Founder and CEO of Dotmini Software.
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation

enum ToolTier: CaseIterable {
    case core
    case navigation
    case editing
    case planning
    case lsp
    case device
    case execution
    case science
    case multimodal
    case studio
    case mcp
}

struct ToolScope {
    static let minimal: Set<ToolTier> = [.core, .mcp]
    static let standard: Set<ToolTier> = [.core, .navigation, .editing, .planning, .lsp, .mcp]
    static let full: Set<ToolTier> = Set(ToolTier.allCases)
    
    static func scopeFor(
        prompt: String = "",
        complexity: TaskComplexity,
        domain: AgentDomain?,
        hasMobilePreview: Bool,
        hasMediaAttachments: Bool = false
    ) -> Set<ToolTier> {
        var tiers: Set<ToolTier> = [.core, .navigation, .editing, .planning, .lsp, .mcp]
        let lower = prompt.lowercased()
        
        if domain == .science || lower.contains("pdb") || lower.contains("alphafold") || lower.contains("protein") || lower.contains("fasta") || lower.contains("mmcif") {
            tiers.insert(.science)
        }
        if hasMobilePreview || lower.contains("preview") || lower.contains("browser") || lower.contains("simulator") || lower.contains("emulator") || lower.contains("screenshot") || lower.contains("inspect") || lower.contains("device") {
            tiers.insert(.device)
        }
        if lower.contains("playground") || lower.contains("cell") || lower.contains("notebook") || lower.contains("ardium") || lower.contains(".ar ") || lower.hasSuffix(".ar") {
            tiers.insert(.execution)
        }
        if hasMediaAttachments || lower.contains("image") || lower.contains("video") || lower.contains("music") || lower.contains("audio") || lower.contains("pdf") || lower.contains("voice") || lower.contains(" picture") || lower.contains("รูป") || lower.contains("วิดีโอ") || lower.contains("เพลง") {
            tiers.insert(.multimodal)
        }
        if lower.contains("database") || lower.contains("sql") || lower.contains("sqlite") || lower.contains("postgres") || lower.contains("api_studio") || lower.contains("database_studio") || lower.contains("postman") || lower.contains("graphql") {
            tiers.insert(.studio)
        }
        
        return tiers
    }
    
    static let toolTierMap: [String: ToolTier] = [
        // Core
        "file_read": .core, "file_write": .core, "replace_in_file": .core,
        "multi_replace_in_file": .core, "apply_patch": .core,
        "grep_search": .core, "shell": .core, "git_status": .core,
        "skill_engine": .core,
        // MCP & Orchestration
        "mcp_orchestrator": .mcp,
        // Navigation
        "find_symbol": .navigation, "list_directory_tree": .navigation,
        "file_search": .navigation, "multi_file_read": .navigation,
        "git_diff": .navigation, "git_log": .navigation,
        "repo_map": .navigation, "web_fetch": .navigation,
        "editor_control": .navigation,
        // Editing
        "patch_file": .editing, "create_directory": .editing,
        "rename_file": .editing,
        // Planning & Multi-Agent
        "agent_plan": .planning, "create_plan": .planning,
        "invoke_subagent": .planning, "define_subagent": .planning,
        "send_message": .planning, "manage_subagents": .planning,
        "swarm_orchestrator": .planning, "background_agent": .planning,
        // LSP
        "get_diagnostics": .lsp, "lsp_diagnostics": .lsp, "lsp_hover": .lsp,
        "lsp_definition": .lsp, "lsp_completions": .lsp,
        "lsp_status": .lsp,
        // Device & Preview
        "device_runtime": .device, "preview_control": .device,
        "visual_regression": .device, "ide_browser": .device,
        // Execution (Playground / Cell / Ardium)
        "playground_run": .execution, "cell_run": .execution,
        "ardium_run": .execution,
        // Science
        "science_inspect": .science, "alphafold_validate": .science,
        "alphafold_input_validate": .science,
        // Multimodal & Media Generation
        "generate_image": .multimodal, "generate_video": .multimodal,
        "generate_music": .multimodal, "inspect_image": .multimodal,
        "extract_pdf": .multimodal, "voice_coding": .multimodal,
        // Studio
        "api_studio": .studio, "database_studio": .studio
    ]
}
