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
    case mcp
}

struct ToolScope {
    static let minimal: Set<ToolTier> = [.core]
    static let standard: Set<ToolTier> = [.core, .navigation, .editing, .lsp]
    static let full: Set<ToolTier> = Set(ToolTier.allCases)
    
    static func scopeFor(complexity: TaskComplexity, domain: AgentDomain?, hasMobilePreview: Bool) -> Set<ToolTier> {
        var tiers: Set<ToolTier> = [.core]
        
        switch complexity {
        case .trivial, .simple:
            tiers.insert(.navigation)
        case .moderate:
            tiers.formUnion([.navigation, .editing, .lsp])
        case .complex, .reasoning:
            tiers.formUnion([.navigation, .editing, .lsp, .planning])
        }
        
        if domain == .science {
            tiers.insert(.science)
        }
        if hasMobilePreview {
            tiers.insert(.device)
        }
        
        tiers.insert(.mcp)
        
        return tiers
    }
    
    static let toolTierMap: [String: ToolTier] = [
        "file_read": .core, "file_write": .core, "replace_in_file": .core,
        "grep_search": .core, "shell": .core, "git_status": .core,
        "find_symbol": .navigation, "list_directory_tree": .navigation,
        "file_search": .navigation, "multi_file_read": .navigation,
        "git_diff": .navigation, "git_log": .navigation,
        "patch_file": .editing, "create_directory": .editing,
        "rename_file": .editing,
        "agent_plan": .planning, "create_plan": .planning,
        "invoke_subagent": .planning, "define_subagent": .planning,
        "send_message": .planning, "manage_subagents": .planning,
        "get_diagnostics": .lsp, "lsp_diagnostics": .lsp, "lsp_hover": .lsp,
        "lsp_definition": .lsp, "lsp_completions": .lsp,
        "lsp_status": .lsp,
        "device_runtime": .device, "preview_control": .device, "visual_regression": .device,
        "playground_run": .execution, "cell_run": .execution,
        "ardium_run": .execution,
        "science_inspect": .science, "alphafold_validate": .science
    ]
}
