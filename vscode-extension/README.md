# MicroCode for VS Code, Cursor, Windsurf & Antigravity (`dotmini.microcode-vscode`)

Official **MicroCode Workstation Extension** bringing MicroCode's native Rust backend, **Ardium v2.3** language toolchain, **Polyglot Shared-Memory Notebooks (`.mcn`)**, **Inline Cell Mode (`# %%`)**, **Dotmini Omni O1X Local AI**, and **35+ MCP Tools** to all VS Code-based editors.

## Key Capabilities

1. **Ardium v2.3 Language Support (`.ar`, `.ardium`)**
   - Full TextMate syntax highlighting (`@owned`, `@State`, `CoreUI`, RAII primitives)
   - Static `@owned` heap allocation ownership analyzer (`ARD-OWNED-001`)
   - Native `arc run`, `arc build`, and `arc lsp` integration
2. **Inline Cell Mode (`# %%` / `// %%`) & In-Memory Playground**
   - Interactive CodeLens above `# %%` and `// %%` blocks in Ardium, Python, Rust, JS/TS, and SQL
   - Zero-file In-Memory Polyglot Playground (`MicroCode: Open In-Memory Polyglot Playground`)
3. **Polyglot Notebooks (`.mcn`)**
   - Native VS Code Notebook serializer & kernel connected to MicroCode Polyglot & Rosetta Shared Memory
4. **Auto-Configure 35+ MicroCode MCP Tools**
   - One-click command (`MicroCode: Auto-Configure MicroCode MCP`) configures `.vscode/mcp.json`, `.cursor/mcp.json`, and `~/.codeium/windsurf/mcp_config.json`
5. **MicroCode Agent & Dotmini Omni O1X Sidebar**
   - Formal Implementation Plan preview with `⌘↵` Approval Gate
   - Direct integration with local Dotmini Sovereign AI (`Omni O1X Pro 3B MoE` / `Lite 0.8B` on `localhost:1234`) and MicroCode Rust Backend (`localhost:3000`)
