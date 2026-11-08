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
    case embedded
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
        
        let scienceHits = ["pdb", "alphafold", "protein", "fasta", "mmcif", "chembl", "molecule", "โปรตีน", "โมเลกุล", "ชีว", "เคมี"]
        if domain == .science || scienceHits.contains(where: { lower.contains($0) }) {
            tiers.insert(.science)
        }
        
        let deviceAndWebHits = [
            "preview", "browser", "simulator", "emulator", "screenshot", "inspect", "device",
            "webapp", "frontend", "localhost", "127.0.0.1", "http://", "https://", "dom", "css", "html",
            "ui", "ux", "layout", "button", "modal", "navbar", "sidebar", "vite", "next", "react", "vue",
            "android", "ios", "adb", "simctl",
            "หน้าเว็บ", "หน้าจอ", "พรีวิว", "เปิดเว็บ", "เบราว์เซอร์", "บราวเซอร์", "มือถือ", "จำลอง",
            "แอนดรอยด์", "ไอโฟน", "เช็คหน้า", "ดูหน้า", "ปุ่ม", "แสดงผล", "ดีไซน์", "บัง", "เพี้ยน", "คลิก"
        ]
        if hasMobilePreview || deviceAndWebHits.contains(where: { lower.contains($0) }) {
            tiers.insert(.device)
        }
        
        let executionHits = [
            "playground", "cell", "notebook", "ardium", ".ar ", ".mic", "ipynb", "matplotlib", "pandas",
            "เซลล์", "สมุดโน้ต", "โน้ตบุ๊ก", "รันโค้ด", "พล็อต", "กราฟ"
        ]
        if executionHits.contains(where: { lower.contains($0) }) || lower.hasSuffix(".ar") || lower.hasSuffix(".mic") {
            tiers.insert(.execution)
        }
        
        let multimodalHits = [
            "image", "video", "music", "audio", "pdf", "docx", "xlsx", "pptx", "csv", "voice", "picture",
            "รูป", "ภาพ", "สกรีนช็อต", "แคปจอ", "วิดีโอ", "เพลง", "เสียง", "เอกสาร", "ไฟล์แนบ"
        ]
        if hasMediaAttachments || multimodalHits.contains(where: { lower.contains($0) }) {
            tiers.insert(.multimodal)
        }
        
        let studioHits = [
            "database", "sql", "sqlite", "postgres", "mysql", "supabase", "prisma", "drizzle", "migration",
            "api_studio", "database_studio", "postman", "graphql", "endpoint", "webhook", "rest api", "curl",
            "ฐานข้อมูล", "ตาราง", "คิวรี", "ยิง api", "เทส api", "เช็ค api", "หลังบ้าน"
        ]
        if studioHits.contains(where: { lower.contains($0) }) {
            tiers.insert(.studio)
        }
        
        let embeddedHits = [
            "arduino", "esp32", "stm32", "rp2040", "pico", "firmware", "serial", "uart", "baud", "flash",
            "platformio", "arduino-cli", "iot", "embedded", "gpio", "บอร์ด", "ไมโครคอนโทรลเลอร์", "เซนเซอร์", "แฟลช"
        ]
        if embeddedHits.contains(where: { lower.contains($0) }) {
            tiers.insert(.embedded)
        }
        
        if complexity >= .complex {
            tiers.insert(.device)
            tiers.insert(.studio)
        }
        
        return tiers
    }
    
    static let toolTierMap: [String: ToolTier] = [
        // Core
        "attachment_read": .core,
        "file_read": .core, "file_write": .core, "replace_in_file": .core,
        "multi_replace_in_file": .core, "apply_patch": .core,
        "grep_search": .core, "codebase_search": .core, "shell": .core, "git_status": .core,
        "skill_engine": .core, "pns_nervous_system": .core,
        "preview_control": .core, "ide_browser": .core,
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
        // Device, Preview & GUI/ADB Local MCP
        "device_runtime": .device,
        "visual_regression": .device,
        "computer_use": .device,
        "mcp__local__computer_use_observe": .device,
        "mcp__local__computer_use_act": .device,
        "mcp__local__computer_use_batch": .device,
        "mcp__local__computer_use_windows": .device,
        "mcp__local__computer_use_inspect": .device,
        "mcp__local__computer_use_click": .device,
        "mcp__local__computer_use_type": .device,
        "mcp__local__computer_use_shortcut": .device,
        "mcp__local__computer_use_capture": .device,
        "mcp__local__computer_use_live_test": .device,
        "mcp__local__adb_execute": .device,
        // Execution (Playground / Cell / Ardium)
        "playground_run": .execution, "cell_run": .execution,
        "cell_list": .execution, "cell_read": .execution,
        "cell_create": .execution, "cell_update": .execution, "cell_delete": .execution,
        "ardium_run": .execution,
        "mcp__local__ardium_compile": .execution,
        "mcp__local__ardium_test": .execution,
        "mcp__local__ardium_diagnose": .execution,
        // Science
        "science_inspect": .science, "alphafold_validate": .science,
        "alphafold_input_validate": .science,
        // Multimodal & Media Generation
        "generate_image": .multimodal, "generate_video": .multimodal,
        "generate_music": .multimodal, "inspect_image": .multimodal,
        "extract_pdf": .multimodal, "voice_coding": .multimodal,
        // Studio
        "api_studio": .studio, "database_studio": .studio,
        // Embedded / HIL
        "embedded_list_hardware": .embedded, "embedded_compile": .embedded,
        "embedded_flash": .embedded, "embedded_serial_capture": .embedded,
        "embedded_serial_send": .embedded, "embedded_decode_crash": .embedded
    ]
}
