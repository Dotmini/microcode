#!/usr/bin/env python3
"""
MicroCode MCP Server — Model Context Protocol (stdio transport)
=============================================================
Exposes MicroCode's workspace tools to any MCP client:
  - Claude Desktop (Anthropic)
  - Cursor
  - Windsurf
  - Any MCP-compatible editor/agent

Protocol: JSON-RPC 2.0 over stdin/stdout
Spec: https://modelcontextprotocol.io

Usage:
  1. chmod +x mcp-server.py
  2. Add to Claude Desktop config (~/.claude/claude_desktop_config.json):
     {
       "mcpServers": {
         "microcode": {
           "command": "python3",
           "args": ["/path/to/mcp-server.py"],
           "env": { "MICROCODE_WORKSPACE": "/your/project" }
         }
       }
     }

Copyright © 2025 SPU AI CLUB — Dotmini Software
"""

import json
import sys
import os
import subprocess
import re
from pathlib import Path

# ============================================================
# Configuration
# ============================================================

SERVER_NAME = "microcode-mcp"
SERVER_VERSION = "2.0.0"
PROTOCOL_VERSION = "2024-11-05"

# Workspace root — set via env or auto-detect
WORKSPACE = os.environ.get("MICROCODE_WORKSPACE", os.getcwd())

# Security: Allowed paths
ALLOWED_PATHS = [WORKSPACE, "/tmp"]

# ============================================================
# Sandbox Validation
# ============================================================

def validate_path(path: str) -> str:
    """Resolve and validate a file path is within sandbox."""
    resolved = os.path.realpath(os.path.expanduser(path))
    for allowed in ALLOWED_PATHS:
        if resolved.startswith(os.path.realpath(allowed)):
            return resolved
    raise PermissionError(f"Path '{path}' is outside workspace. Access denied.")

# ============================================================
# Tool Implementations
# ============================================================

def tool_file_read(params: dict) -> str:
    path = validate_path(params["path"])
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    if len(content) > 15000:
        return content[:15000] + f"\n\n... (truncated, total: {len(content)} chars)"
    return content

def tool_file_write(params: dict) -> str:
    path = validate_path(params["path"])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    content = params["content"]
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    return f"✅ Written {len(content)} chars to {os.path.basename(path)}"

def tool_replace_in_file(params: dict) -> str:
    path = validate_path(params["path"])
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    old_text = params["old_text"]
    new_text = params["new_text"]
    if old_text not in content:
        raise ValueError(f"Could not find the specified text in {os.path.basename(path)}")
    content = content.replace(old_text, new_text, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    return f"✅ Replaced text in {os.path.basename(path)}"

def tool_grep_search(params: dict) -> str:
    directory = validate_path(params["directory"])
    pattern = params["pattern"]
    args = ["grep", "-rn", "--color=never", "-I", "-m", "50"]
    if "include" in params:
        args.extend(["--include", params["include"]])
    args.extend([pattern, directory])
    result = subprocess.run(args, capture_output=True, text=True, timeout=10)
    output = result.stdout
    if not output:
        return f"No matches found for '{pattern}'"
    if len(output) > 8000:
        return output[:8000] + "\n... (results truncated)"
    return output

def tool_list_directory_tree(params: dict) -> str:
    path = validate_path(params["path"])
    max_depth = params.get("max_depth", 3)
    
    def build_tree(dir_path, prefix, depth):
        if depth >= max_depth:
            return ""
        try:
            entries = sorted(os.listdir(dir_path))
        except PermissionError:
            return ""
        
        # Filter hidden files
        entries = [e for e in entries if not e.startswith(".")]
        result = ""
        for i, entry in enumerate(entries):
            is_last = i == len(entries) - 1
            connector = "└── " if is_last else "├── "
            child_prefix = "    " if is_last else "│   "
            full_path = os.path.join(dir_path, entry)
            is_dir = os.path.isdir(full_path)
            result += f"{prefix}{connector}{entry}{'/' if is_dir else ''}\n"
            if is_dir:
                result += build_tree(full_path, prefix + child_prefix, depth + 1)
        return result
    
    return f"{os.path.basename(path)}/\n{build_tree(path, '', 0)}"

def tool_shell(params: dict) -> str:
    command = params["command"]
    cwd = params.get("cwd", WORKSPACE)
    
    # Security: Block dangerous commands
    dangerous = ["rm -rf /", "mkfs", "dd if=", ":(){ :|:& };:"]
    for d in dangerous:
        if d in command:
            raise PermissionError(f"Blocked dangerous command: {command}")
    
    result = subprocess.run(
        ["zsh", "-c", command],
        capture_output=True, text=True,
        cwd=cwd, timeout=30
    )
    output = result.stdout
    if result.stderr:
        output += f"\n[stderr]\n{result.stderr}"
    if result.returncode != 0:
        output = f"[exit code: {result.returncode}]\n{output}"
    if len(output) > 10000:
        return output[:10000] + "\n... (truncated)"
    return output

def tool_git_status(params: dict) -> str:
    path = validate_path(params["path"])
    result = subprocess.run(
        ["git", "status", "--short"],
        capture_output=True, text=True,
        cwd=path, timeout=10
    )
    return result.stdout or "Clean working tree"

def tool_find_symbol(params: dict) -> str:
    directory = validate_path(params["directory"])
    symbol = params["symbol"]
    symbol_type = params.get("type", "all")
    
    if symbol_type == "function":
        patterns = [f"func\\s+{symbol}", f"def\\s+{symbol}", f"function\\s+{symbol}"]
    elif symbol_type == "class":
        patterns = [f"class\\s+{symbol}", f"interface\\s+{symbol}"]
    elif symbol_type == "struct":
        patterns = [f"struct\\s+{symbol}"]
    else:
        patterns = [f"\\b{symbol}\\b"]
    
    results = ""
    for pattern in patterns:
        r = subprocess.run(
            ["grep", "-rn", "--color=never", "-I", "-E", "-m", "20", pattern, directory],
            capture_output=True, text=True, timeout=10
        )
        results += r.stdout
    
    return results or f"No symbols matching '{symbol}' found"

def tool_create_directory(params: dict) -> str:
    path = validate_path(params["path"])
    os.makedirs(path, exist_ok=True)
    return f"✅ Created directory: {os.path.basename(path)}"

def tool_rename_file(params: dict) -> str:
    old_path = validate_path(params["old_path"])
    new_path = validate_path(params["new_path"])
    os.makedirs(os.path.dirname(new_path), exist_ok=True)
    os.rename(old_path, new_path)
    return f"✅ Renamed: {os.path.basename(old_path)} → {os.path.basename(new_path)}"

def tool_patch_file(params: dict) -> str:
    path = validate_path(params["path"])
    edits_str = params["edits"]
    
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    
    edits = json.loads(edits_str) if isinstance(edits_str, str) else edits_str
    applied = 0
    failed = []
    
    for edit in edits:
        old = edit.get("old", "")
        new = edit.get("new", "")
        if old in content:
            content = content.replace(old, new, 1)
            applied += 1
        else:
            failed.append(f"Not found: {old[:60]}...")
    
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    
    result = f"✅ Applied {applied}/{len(edits)} edits to {os.path.basename(path)}"
    if failed:
        result += "\n⚠️ Failed:\n" + "\n".join(failed)
    return result

def tool_multi_file_read(params: dict) -> str:
    paths_str = params["paths"]
    max_lines = params.get("max_lines", 100)
    paths = [p.strip() for p in paths_str.split(",")]
    
    result = ""
    total_chars = 0
    
    for p in paths:
        if total_chars > 12000:
            result += "\n--- (remaining files skipped) ---"
            break
        try:
            resolved = validate_path(p)
            with open(resolved, "r", encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
            limited = lines[:max_lines]
            content = "".join(limited)
            truncated = len(lines) > max_lines
            
            result += f"\n═══ {os.path.basename(p)} ═══\n{content}"
            if truncated:
                result += f"\n... ({len(lines) - max_lines} more lines)"
            total_chars += len(content)
        except Exception as e:
            result += f"\n═══ {os.path.basename(p)} ═══\n⚠️ Error: {e}\n"
    
    return result

def tool_web_fetch(params: dict) -> str:
    import urllib.request
    url = params["url"]
    req = urllib.request.Request(url, headers={"User-Agent": "MicroCode-MCP/2.0"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        content = resp.read().decode("utf-8", errors="replace")
    if len(content) > 5000:
        return content[:5000] + "\n... (truncated)"
    return content

# ============================================================
# Cell Mode — Notebook-style Code Cells (CRUD + Execute)
# ============================================================

CELLS_DIR = os.path.join(WORKSPACE, ".microcode", "cells")
LANG_RUNNERS = {
    "python": ["python3", "-u"],
    "python3": ["python3", "-u"],
    "javascript": ["node", "-e"],
    "node": ["node", "-e"],
    "typescript": ["npx", "tsx", "-e"],
    "swift": ["swift", "-e"],
    "ruby": ["ruby", "-e"],
    "bash": ["bash", "-c"],
    "zsh": ["zsh", "-c"],
    "shell": ["zsh", "-c"],
    "rust": None,  # Special handling
    "java": None,  # Special handling
    "go": None,    # Special handling
    "c": None,     # Special handling
    "cpp": None,   # Special handling
}
LANG_EXT = {
    "python": ".py", "python3": ".py", "javascript": ".js", "node": ".js",
    "typescript": ".ts", "swift": ".swift", "ruby": ".rb", "bash": ".sh",
    "zsh": ".sh", "shell": ".sh", "rust": ".rs", "java": ".java",
    "go": ".go", "c": ".c", "cpp": ".cpp",
}

def _ensure_cells_dir():
    os.makedirs(CELLS_DIR, exist_ok=True)

def _cell_path(cell_id: str) -> str:
    return os.path.join(CELLS_DIR, f"{cell_id}.json")

def _load_cell(cell_id: str) -> dict:
    path = _cell_path(cell_id)
    if not os.path.exists(path):
        raise FileNotFoundError(f"Cell '{cell_id}' not found")
    with open(path, "r") as f:
        return json.load(f)

def _save_cell(cell: dict):
    _ensure_cells_dir()
    with open(_cell_path(cell["id"]), "w") as f:
        json.dump(cell, f, indent=2, default=str)

def tool_cell_create(params: dict) -> str:
    import uuid, datetime
    _ensure_cells_dir()
    cell_id = params.get("id", str(uuid.uuid4())[:8])
    cell = {
        "id": cell_id,
        "language": params.get("language", "python"),
        "code": params.get("code", ""),
        "output": "",
        "status": "idle",
        "color": params.get("color", "blue"),
        "title": params.get("title", f"Cell {cell_id}"),
        "created_at": datetime.datetime.now().isoformat(),
        "updated_at": datetime.datetime.now().isoformat(),
    }
    _save_cell(cell)
    return json.dumps({"status": "created", "cell": cell}, indent=2)

def tool_cell_read(params: dict) -> str:
    cell = _load_cell(params["id"])
    return json.dumps(cell, indent=2)

def tool_cell_update(params: dict) -> str:
    import datetime
    cell = _load_cell(params["id"])
    for key in ["code", "language", "title", "color"]:
        if key in params:
            cell[key] = params[key]
    cell["updated_at"] = datetime.datetime.now().isoformat()
    _save_cell(cell)
    return json.dumps({"status": "updated", "cell": cell}, indent=2)

def tool_cell_delete(params: dict) -> str:
    path = _cell_path(params["id"])
    if os.path.exists(path):
        os.remove(path)
        return f"✅ Cell '{params['id']}' deleted"
    raise FileNotFoundError(f"Cell '{params['id']}' not found")

def tool_cell_list(params: dict) -> str:
    _ensure_cells_dir()
    cells = []
    for f in sorted(os.listdir(CELLS_DIR)):
        if f.endswith(".json"):
            try:
                with open(os.path.join(CELLS_DIR, f)) as fh:
                    cell = json.load(fh)
                    cells.append({"id": cell["id"], "title": cell.get("title",""), "language": cell["language"], "status": cell.get("status","idle"), "lines": len(cell.get("code","").split("\n"))})
            except: pass
    return json.dumps({"count": len(cells), "cells": cells}, indent=2)

def _run_code(language: str, code: str, cwd: str = None) -> tuple:
    """Run code and return (stdout, stderr, exit_code)."""
    lang = language.lower()
    runner = LANG_RUNNERS.get(lang)
    
    if runner is None:
        # Compiled languages — write to temp file, compile, run
        ext = LANG_EXT.get(lang, ".txt")
        import tempfile
        tmp = tempfile.NamedTemporaryFile(suffix=ext, mode="w", delete=False, dir=cwd or WORKSPACE)
        tmp.write(code)
        tmp.close()
        try:
            if lang == "rust":
                out_bin = tmp.name.replace(".rs", "")
                cr = subprocess.run(["rustc", tmp.name, "-o", out_bin], capture_output=True, text=True, timeout=30)
                if cr.returncode != 0:
                    return "", cr.stderr, cr.returncode
                r = subprocess.run([out_bin], capture_output=True, text=True, timeout=30, cwd=cwd)
                os.remove(out_bin)
                return r.stdout, r.stderr, r.returncode
            elif lang in ("c", "cpp"):
                compiler = "gcc" if lang == "c" else "g++"
                out_bin = tmp.name.replace(ext, "")
                cr = subprocess.run([compiler, tmp.name, "-o", out_bin], capture_output=True, text=True, timeout=30)
                if cr.returncode != 0:
                    return "", cr.stderr, cr.returncode
                r = subprocess.run([out_bin], capture_output=True, text=True, timeout=30, cwd=cwd)
                os.remove(out_bin)
                return r.stdout, r.stderr, r.returncode
            elif lang == "java":
                cr = subprocess.run(["javac", tmp.name], capture_output=True, text=True, timeout=30)
                if cr.returncode != 0:
                    return "", cr.stderr, cr.returncode
                classname = os.path.basename(tmp.name).replace(".java", "")
                r = subprocess.run(["java", "-cp", os.path.dirname(tmp.name), classname], capture_output=True, text=True, timeout=30)
                return r.stdout, r.stderr, r.returncode
            elif lang == "go":
                r = subprocess.run(["go", "run", tmp.name], capture_output=True, text=True, timeout=30, cwd=cwd)
                return r.stdout, r.stderr, r.returncode
            else:
                return "", f"Unsupported compiled language: {lang}", 1
        finally:
            os.remove(tmp.name)
    
    # Interpreted languages
    if lang in ("javascript", "node", "typescript", "swift", "ruby"):
        # -e style: pass code as argument
        r = subprocess.run(runner + [code], capture_output=True, text=True, timeout=30, cwd=cwd or WORKSPACE)
    else:
        # stdin-based (python, bash, zsh)
        r = subprocess.run(runner[:-1] if lang.startswith("python") else runner, input=code, capture_output=True, text=True, timeout=30, cwd=cwd or WORKSPACE)
    
    return r.stdout, r.stderr, r.returncode

def tool_cell_run(params: dict) -> str:
    import datetime
    cell = _load_cell(params["id"])
    cell["status"] = "running"
    _save_cell(cell)
    
    try:
        stdout, stderr, exit_code = _run_code(cell["language"], cell["code"])
        output = stdout
        if stderr:
            output += f"\n[stderr]\n{stderr}"
        if exit_code != 0:
            output = f"[exit code: {exit_code}]\n{output}"
            cell["status"] = "error"
        else:
            cell["status"] = "success"
        
        if len(output) > 10000:
            output = output[:10000] + "\n... (truncated)"
        cell["output"] = output
        cell["updated_at"] = datetime.datetime.now().isoformat()
        _save_cell(cell)
        return json.dumps({"status": cell["status"], "output": output, "exit_code": exit_code}, indent=2)
    except subprocess.TimeoutExpired:
        cell["status"] = "timeout"
        cell["output"] = "⏱ Execution timed out (30s limit)"
        _save_cell(cell)
        return json.dumps({"status": "timeout", "output": cell["output"]})
    except Exception as e:
        cell["status"] = "error"
        cell["output"] = str(e)
        _save_cell(cell)
        return json.dumps({"status": "error", "output": str(e)})

def tool_playground_run(params: dict) -> str:
    """Run code directly without creating a persistent cell."""
    language = params.get("language", "python")
    code = params["code"]
    cwd = params.get("cwd", WORKSPACE)
    
    try:
        stdout, stderr, exit_code = _run_code(language, code, cwd)
        output = stdout
        if stderr:
            output += f"\n[stderr]\n{stderr}"
        if exit_code != 0:
            output = f"[exit code: {exit_code}]\n{output}"
        if len(output) > 10000:
            output = output[:10000] + "\n... (truncated)"
        return output or "(no output)"
    except subprocess.TimeoutExpired:
        return "⏱ Execution timed out (30s limit)"

def tool_git_diff(params: dict) -> str:
    path = validate_path(params.get("path", WORKSPACE))
    staged = params.get("staged", False)
    args = ["git", "diff"]
    if staged:
        args.append("--staged")
    args.append("--stat")
    r = subprocess.run(args, capture_output=True, text=True, cwd=path, timeout=10)
    stat = r.stdout
    args2 = ["git", "diff"]
    if staged:
        args2.append("--staged")
    r2 = subprocess.run(args2, capture_output=True, text=True, cwd=path, timeout=10)
    diff = r2.stdout
    if len(diff) > 8000:
        diff = diff[:8000] + "\n... (truncated)"
    return f"{stat}\n{diff}" if diff else "No changes"

# ============================================================
# Tool Registry
# ============================================================

TOOLS = {
    "file_read": {
        "description": "Read the contents of a file",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute file path to read"}
            },
            "required": ["path"]
        },
        "handler": tool_file_read
    },
    "file_write": {
        "description": "Write content to a file (creates parent dirs if needed)",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute file path to write"},
                "content": {"type": "string", "description": "Content to write"}
            },
            "required": ["path", "content"]
        },
        "handler": tool_file_write
    },
    "replace_in_file": {
        "description": "Find and replace text in a file (targeted edit)",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute file path"},
                "old_text": {"type": "string", "description": "Exact text to find"},
                "new_text": {"type": "string", "description": "Replacement text"}
            },
            "required": ["path", "old_text", "new_text"]
        },
        "handler": tool_replace_in_file
    },
    "grep_search": {
        "description": "Search for a pattern across files using grep",
        "inputSchema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string", "description": "Search pattern (regex)"},
                "directory": {"type": "string", "description": "Directory to search"},
                "include": {"type": "string", "description": "File glob (e.g. '*.swift')"}
            },
            "required": ["pattern", "directory"]
        },
        "handler": tool_grep_search
    },
    "list_directory_tree": {
        "description": "List directory structure as a tree",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Directory path"},
                "max_depth": {"type": "integer", "description": "Max depth (default: 3)"}
            },
            "required": ["path"]
        },
        "handler": tool_list_directory_tree
    },
    "shell": {
        "description": "Execute a shell command (zsh)",
        "inputSchema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "Shell command to run"},
                "cwd": {"type": "string", "description": "Working directory"}
            },
            "required": ["command"]
        },
        "handler": tool_shell
    },
    "git_status": {
        "description": "Get git status of a repository",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Repository path"}
            },
            "required": ["path"]
        },
        "handler": tool_git_status
    },
    "git_diff": {
        "description": "Get git diff (staged or unstaged changes)",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Repository path"},
                "staged": {"type": "boolean", "description": "Show staged changes only"}
            },
            "required": []
        },
        "handler": tool_git_diff
    },
    "find_symbol": {
        "description": "Find function/class/struct definitions in workspace",
        "inputSchema": {
            "type": "object",
            "properties": {
                "symbol": {"type": "string", "description": "Symbol name to find"},
                "directory": {"type": "string", "description": "Directory to search"},
                "type": {"type": "string", "description": "function|class|struct|enum|all"}
            },
            "required": ["symbol", "directory"]
        },
        "handler": tool_find_symbol
    },
    "create_directory": {
        "description": "Create a directory (with parents)",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Directory path to create"}
            },
            "required": ["path"]
        },
        "handler": tool_create_directory
    },
    "rename_file": {
        "description": "Rename or move a file",
        "inputSchema": {
            "type": "object",
            "properties": {
                "old_path": {"type": "string", "description": "Current file path"},
                "new_path": {"type": "string", "description": "New file path"}
            },
            "required": ["old_path", "new_path"]
        },
        "handler": tool_rename_file
    },
    "patch_file": {
        "description": "Apply multiple find-and-replace edits to a file at once",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute file path"},
                "edits": {"type": "string", "description": 'JSON array: [{"old":"...","new":"..."}]'}
            },
            "required": ["path", "edits"]
        },
        "handler": tool_patch_file
    },
    "multi_file_read": {
        "description": "Read multiple files at once (comma-separated paths)",
        "inputSchema": {
            "type": "object",
            "properties": {
                "paths": {"type": "string", "description": "Comma-separated file paths"},
                "max_lines": {"type": "integer", "description": "Max lines per file (default: 100)"}
            },
            "required": ["paths"]
        },
        "handler": tool_multi_file_read
    },
    "web_fetch": {
        "description": "Fetch content from a URL",
        "inputSchema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "URL to fetch"}
            },
            "required": ["url"]
        },
        "handler": tool_web_fetch
    },
    # --- Cell Mode Tools ---
    "cell_create": {
        "description": "Create a new code cell (notebook-style). Supports Python, JavaScript, Swift, Rust, Go, C, C++, Java, Ruby, Bash.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "Cell ID (auto-generated if omitted)"},
                "language": {"type": "string", "description": "Language: python, javascript, swift, rust, go, c, cpp, java, ruby, bash"},
                "code": {"type": "string", "description": "Source code for the cell"},
                "title": {"type": "string", "description": "Cell title/description"},
                "color": {"type": "string", "description": "Cell color tag (blue, green, red, purple, orange)"}
            },
            "required": ["code"]
        },
        "handler": tool_cell_create
    },
    "cell_read": {
        "description": "Read a cell's code, output, and metadata",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "Cell ID to read"}
            },
            "required": ["id"]
        },
        "handler": tool_cell_read
    },
    "cell_update": {
        "description": "Update a cell's code, language, title, or color",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "Cell ID to update"},
                "code": {"type": "string", "description": "New source code"},
                "language": {"type": "string", "description": "New language"},
                "title": {"type": "string", "description": "New title"},
                "color": {"type": "string", "description": "New color tag"}
            },
            "required": ["id"]
        },
        "handler": tool_cell_update
    },
    "cell_delete": {
        "description": "Delete a code cell",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "Cell ID to delete"}
            },
            "required": ["id"]
        },
        "handler": tool_cell_delete
    },
    "cell_list": {
        "description": "List all code cells in the notebook",
        "inputSchema": {
            "type": "object",
            "properties": {}
        },
        "handler": tool_cell_list
    },
    "cell_run": {
        "description": "Execute a code cell and return its output. Supports 12+ languages with real-time compilation.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "Cell ID to execute"}
            },
            "required": ["id"]
        },
        "handler": tool_cell_run
    },
    "playground_run": {
        "description": "Run code instantly without creating a cell (playground/scratch mode). Supports Python, JS, Swift, Rust, Go, C, C++, Java, Ruby, Bash.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "language": {"type": "string", "description": "Language: python, javascript, swift, rust, go, c, cpp, java, ruby, bash"},
                "code": {"type": "string", "description": "Source code to execute"},
                "cwd": {"type": "string", "description": "Working directory (optional)"}
            },
            "required": ["code"]
        },
        "handler": tool_playground_run
    },
}

# ============================================================
# MCP Protocol Handler (JSON-RPC 2.0 over stdio)
# ============================================================

def handle_request(request: dict) -> dict:
    """Handle a single JSON-RPC request."""
    method = request.get("method", "")
    req_id = request.get("id")
    params = request.get("params", {})
    
    # --- Lifecycle ---
    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {
                    "tools": {"listChanged": False},
                    "resources": {"subscribe": False, "listChanged": False}
                },
                "serverInfo": {
                    "name": SERVER_NAME,
                    "version": SERVER_VERSION
                }
            }
        }
    
    if method == "notifications/initialized":
        return None  # No response needed for notifications
    
    # --- Tools ---
    if method == "tools/list":
        tool_list = []
        for name, info in TOOLS.items():
            tool_list.append({
                "name": name,
                "description": info["description"],
                "inputSchema": info["inputSchema"]
            })
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {"tools": tool_list}
        }
    
    if method == "tools/call":
        tool_name = params.get("name", "")
        tool_args = params.get("arguments", {})
        
        if tool_name not in TOOLS:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": f"Error: Unknown tool '{tool_name}'"}],
                    "isError": True
                }
            }
        
        try:
            result = TOOLS[tool_name]["handler"](tool_args)
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": result}],
                    "isError": False
                }
            }
        except Exception as e:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": f"Error: {str(e)}"}],
                    "isError": True
                }
            }
    
    # --- Resources ---
    if method == "resources/list":
        resources = []
        # Expose workspace files as resources
        workspace_path = Path(WORKSPACE)
        if workspace_path.exists():
            resources.append({
                "uri": f"file://{WORKSPACE}",
                "name": workspace_path.name,
                "description": f"MicroCode workspace: {WORKSPACE}",
                "mimeType": "text/plain"
            })
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {"resources": resources}
        }
    
    if method == "resources/read":
        uri = params.get("uri", "")
        if uri.startswith("file://"):
            path = uri[7:]
            try:
                validated = validate_path(path)
                with open(validated, "r", encoding="utf-8", errors="replace") as f:
                    content = f.read()
                return {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "contents": [{"uri": uri, "mimeType": "text/plain", "text": content}]
                    }
                }
            except Exception as e:
                return error_response(req_id, -32000, str(e))
    
    # --- Ping ---
    if method == "ping":
        return {"jsonrpc": "2.0", "id": req_id, "result": {}}
    
    # Unknown method
    return error_response(req_id, -32601, f"Method not found: {method}")

def error_response(req_id, code: int, message: str) -> dict:
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {"code": code, "message": message}
    }

# ============================================================
# Main Event Loop (stdio transport)
# ============================================================

def main():
    """Read JSON-RPC messages from stdin, write responses to stdout."""
    log(f"MicroCode MCP Server v{SERVER_VERSION} started")
    log(f"Workspace: {WORKSPACE}")
    log(f"Tools: {len(TOOLS)} available")
    
    buffer = ""
    
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break  # EOF
            
            line = line.strip()
            if not line:
                continue
            
            try:
                request = json.loads(line)
            except json.JSONDecodeError:
                # Try reading Content-Length header (some clients use HTTP-style framing)
                if line.startswith("Content-Length:"):
                    length = int(line.split(":")[1].strip())
                    sys.stdin.readline()  # Empty line
                    body = sys.stdin.read(length)
                    request = json.loads(body)
                else:
                    continue
            
            response = handle_request(request)
            
            if response is not None:
                response_json = json.dumps(response)
                # Write with Content-Length header for compatibility
                sys.stdout.write(response_json + "\n")
                sys.stdout.flush()
                
        except KeyboardInterrupt:
            break
        except Exception as e:
            log(f"Error: {e}")
            continue
    
    log("MicroCode MCP Server stopped")

def log(message: str):
    """Log to stderr (stdout is reserved for JSON-RPC)."""
    sys.stderr.write(f"[microcode-mcp] {message}\n")
    sys.stderr.flush()

if __name__ == "__main__":
    main()
