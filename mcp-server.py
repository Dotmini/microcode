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
import shlex
from pathlib import Path

# ============================================================
# Configuration
# ============================================================

SERVER_NAME = "microcode-mcp"
SERVER_VERSION = "2.0.1"
PROTOCOL_VERSION = "2024-11-05"

# Workspace root — set via env or auto-detect
WORKSPACE = os.path.realpath(os.path.expanduser(os.environ.get("MICROCODE_WORKSPACE", os.getcwd())))

# Security: Allowed paths
ALLOWED_PATHS = [WORKSPACE, "/tmp"]

# ============================================================
# Sandbox Validation
# ============================================================

def validate_path(path: str) -> str:
    """Resolve and validate a file path is strictly within allowed sandbox directories."""
    expanded = os.path.expanduser(path)
    candidate = expanded if os.path.isabs(expanded) else os.path.join(WORKSPACE, expanded)
    resolved = os.path.realpath(candidate)
    for allowed in ALLOWED_PATHS:
        allowed_resolved = os.path.realpath(os.path.expanduser(allowed))
        try:
            # Must share commonpath and not be a sibling prefix bypass
            common = os.path.commonpath([resolved, allowed_resolved])
            if common == allowed_resolved:
                return resolved
        except ValueError:
            continue
    raise PermissionError(f"Path '{path}' is outside workspace. Access denied.")

def validate_workspace_path(path: str) -> str:
    """Like validate_path, but excludes /tmp for commands that execute code."""
    resolved = validate_path(path)
    if os.path.commonpath([resolved, WORKSPACE]) != WORKSPACE:
        raise PermissionError("Execution must remain inside the active workspace.")
    return resolved

def validate_cell_id(cell_id: str) -> str:
    """Cell IDs are filenames, never paths."""
    if not isinstance(cell_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", cell_id):
        raise ValueError("Invalid cell id")
    return cell_id

def validate_read_only_shell(command: str) -> list[str]:
    """Allow only simple, non-mutating workspace inspection commands.

    This server is invoked by autonomous models. A blacklist cannot safely
    contain a shell, so commands requiring writes or execution must go through
    an explicit user-approved execution flow in the app instead.
    """
    if not isinstance(command, str) or not command.strip():
        raise ValueError("Command is required")
    if any(token in command for token in (";", "|", "&", ">", "<", "`", "$", "\n", "\r")):
        raise PermissionError("Shell composition, redirection, and substitution require explicit user approval.")
    args = shlex.split(command)
    if not args:
        raise ValueError("Command is required")
    allowed = {"git", "rg", "grep", "find", "ls", "pwd", "head", "tail", "sed", "wc", "stat"}
    if args[0] not in allowed:
        raise PermissionError("Only read-only workspace inspection commands are available through MCP.")
    if any(arg.startswith("/") or ".." in arg for arg in args[1:]):
        raise PermissionError("Absolute paths and parent traversal are not allowed in MCP terminal commands.")
    if args[0] == "git" and len(args) > 1 and args[1] not in {"status", "diff", "log", "branch", "show", "rev-parse"}:
        raise PermissionError("Only read-only git operations are available through MCP.")
    if args[0] == "find" and any(arg in {"-delete", "-exec", "-execdir"} for arg in args[1:]):
        raise PermissionError("Mutating find actions are not allowed through MCP.")
    return args

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
    cwd = validate_workspace_path(params.get("cwd", WORKSPACE))
    validate_read_only_shell(command)
    
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
    "r": ["Rscript", "-e"],
    "rscript": ["Rscript", "-e"],
    "julia": ["julia", "-e"],
    "jl": ["julia", "-e"],
    "javascript": ["node", "-e"],
    "node": ["node", "-e"],
    "typescript": ["npx", "tsx", "-e"],
    "swift": ["swift", "-e"],
    "ruby": ["ruby", "-e"],
    "php": ["php", "-r"],
    "lua": ["lua", "-e"],
    "perl": ["perl", "-e"],
    "bash": ["bash", "-c"],
    "zsh": ["zsh", "-c"],
    "shell": ["zsh", "-c"],
    "zig": None,
    "dart": None,
    "csharp": None,
    "cs": None,
    "dotnet": None,
    "rust": None,
    "rs": None,
    "java": None,
    "go": None,
    "c": None,
    "cpp": None,
    "objc": None,
    "ardium": None,
    "ar": None,
    "sql": None,
}
LANG_EXT = {
    "python": ".py", "python3": ".py", "r": ".R", "rscript": ".R", "julia": ".jl", "jl": ".jl",
    "javascript": ".js", "node": ".js", "typescript": ".ts", "swift": ".swift", "ruby": ".rb",
    "php": ".php", "lua": ".lua", "perl": ".pl", "bash": ".sh", "zsh": ".sh", "shell": ".sh",
    "zig": ".zig", "dart": ".dart", "csharp": ".cs", "cs": ".cs", "dotnet": ".cs",
    "rust": ".rs", "rs": ".rs", "java": ".java", "go": ".go", "c": ".c", "cpp": ".cpp",
    "objc": ".m", "ardium": ".ar", "ar": ".ar", "sql": ".sql",
}

def _find_ardium_bin() -> str:
    env_bin = os.environ.get("ARDIUM_BIN")
    if env_bin and os.path.exists(env_bin):
        return env_bin
    home = os.path.expanduser("~")
    candidates = [
        os.path.join(home, ".cargo/bin/arc"),
        os.path.join(home, ".cargo/bin/TitanScript"),
        "/opt/homebrew/bin/arc",
        "/usr/local/bin/arc",
        "/usr/local/ardium/bin/arc",
        "/usr/local/bin/ardium",
        "/usr/local/ardium/ardium",
        "/opt/homebrew/bin/ardium",
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
    return "/usr/local/ardium/bin/arc"

def _ensure_cells_dir():
    os.makedirs(CELLS_DIR, exist_ok=True)

def _cell_path(cell_id: str) -> str:
    return os.path.join(CELLS_DIR, f"{validate_cell_id(cell_id)}.json")

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
    cell_id = validate_cell_id(params.get("id", str(uuid.uuid4())[:8]))
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
            if lang in ("rust", "rs"):
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
            elif lang in ("objc", "m", "mm"):
                out_bin = tmp.name.replace(ext, "")
                cr = subprocess.run(["clang", "-framework", "Foundation", tmp.name, "-o", out_bin], capture_output=True, text=True, timeout=30)
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
            elif lang in ("csharp", "cs", "dotnet"):
                r = subprocess.run(["dotnet-script", tmp.name], capture_output=True, text=True, timeout=30, cwd=cwd)
                return r.stdout, r.stderr, r.returncode
            elif lang == "zig":
                r = subprocess.run(["zig", "run", tmp.name], capture_output=True, text=True, timeout=30, cwd=cwd)
                return r.stdout, r.stderr, r.returncode
            elif lang == "dart":
                r = subprocess.run(["dart", "run", tmp.name], capture_output=True, text=True, timeout=30, cwd=cwd)
                return r.stdout, r.stderr, r.returncode
            elif lang == "sql":
                with open(tmp.name, "r") as fh:
                    sql_input = fh.read()
                r = subprocess.run(["sqlite3", ":memory:"], input=sql_input, capture_output=True, text=True, timeout=30, cwd=cwd)
                return r.stdout, r.stderr, r.returncode
            elif lang in ("ardium", "ar"):
                ardium_bin = _find_ardium_bin()
                env = os.environ.copy()
                env["DYLD_LIBRARY_PATH"] = f"/usr/local/ardium/lib:{env.get('DYLD_LIBRARY_PATH', '')}"
                env["ARDIUM_LIB_PATH"] = "/usr/local/ardium/lib"
                env["ARDIUM_STDLIB"] = "/usr/local/ardium/stdlib"
                r = subprocess.run([ardium_bin, "run", tmp.name], capture_output=True, text=True, timeout=30, cwd=cwd or WORKSPACE, env=env)
                clean_stdout = "\n".join([line for line in r.stdout.splitlines() if "Target Triple" not in line])
                clean_stderr = "\n".join([line for line in r.stderr.splitlines() if "Target Triple" not in line])
                return clean_stdout, clean_stderr, r.returncode
            else:
                return "", f"Unsupported compiled language: {lang}", 1
        finally:
            os.remove(tmp.name)
    
    # Interpreted languages
    if lang in ("javascript", "node", "typescript", "swift", "ruby", "r", "rscript", "julia", "jl", "php", "lua", "perl"):
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
    cwd = validate_workspace_path(params.get("cwd", WORKSPACE))
    
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

def tool_ardium_run(params: dict) -> str:
    """Execute Ardium (.ar) source code or file directly."""
    code = params.get("code")
    file_path = params.get("path")
    cwd = validate_workspace_path(params.get("cwd", WORKSPACE))
    
    ardium_bin = _find_ardium_bin()
    if not os.path.exists(ardium_bin):
        return "❌ Error: Ardium compiler binary (arc / ardium) not found on system."

    env = os.environ.copy()
    env["DYLD_LIBRARY_PATH"] = f"/usr/local/ardium/lib:{env.get('DYLD_LIBRARY_PATH', '')}"
    env["ARDIUM_LIB_PATH"] = "/usr/local/ardium/lib"
    env["ARDIUM_STDLIB"] = "/usr/local/ardium/stdlib"

    if file_path:
        target = validate_path(file_path)
        r = subprocess.run([ardium_bin, "run", target], capture_output=True, text=True, timeout=30, cwd=cwd, env=env)
        out = r.stdout
        if r.stderr:
            out += f"\n[stderr]\n{r.stderr}"
        if r.returncode != 0:
            out = f"[exit code: {r.returncode}]\n{out}"
        return out or "(no output)"
    elif code:
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".ar", mode="w", delete=False, dir=cwd or WORKSPACE) as tmp:
            tmp.write(code)
            tmp_name = tmp.name
        try:
            r = subprocess.run([ardium_bin, "run", tmp_name], capture_output=True, text=True, timeout=30, cwd=cwd, env=env)
            out = r.stdout
            if r.stderr:
                out += f"\n[stderr]\n{r.stderr}"
            if r.returncode != 0:
                out = f"[exit code: {r.returncode}]\n{out}"
            return out or "(no output)"
        finally:
            if os.path.exists(tmp_name):
                os.remove(tmp_name)
    else:
        raise ValueError("Either 'code' or 'path' must be provided.")

def tool_ardium_compile(params: dict) -> str:
    """Compile Ardium source file to native binary executable."""
    source_path = validate_path(params["path"])
    output_path = validate_workspace_path(params.get("output", source_path.replace(".ar", "")))
    
    ardium_bin = _find_ardium_bin()
    env = os.environ.copy()
    env["DYLD_LIBRARY_PATH"] = f"/usr/local/ardium/lib:{env.get('DYLD_LIBRARY_PATH', '')}"
    env["ARDIUM_LIB_PATH"] = "/usr/local/ardium/lib"
    env["ARDIUM_STDLIB"] = "/usr/local/ardium/stdlib"
    
    args = [ardium_bin, "build", source_path, "-o", output_path]
    r = subprocess.run(args, capture_output=True, text=True, timeout=60, env=env)
    if r.returncode != 0:
        return f"❌ Compilation Failed:\n{r.stderr or r.stdout}"
    return f"✅ Ardium binary compiled successfully to: {output_path}"

def tool_ardium_test(params: dict) -> str:
    """Run test suites in an Ardium project or file."""
    path = validate_path(params.get("path", WORKSPACE))
    ardium_bin = _find_ardium_bin()
    env = os.environ.copy()
    env["DYLD_LIBRARY_PATH"] = f"/usr/local/ardium/lib:{env.get('DYLD_LIBRARY_PATH', '')}"
    env["ARDIUM_LIB_PATH"] = "/usr/local/ardium/lib"
    env["ARDIUM_STDLIB"] = "/usr/local/ardium/stdlib"
    
    r = subprocess.run([ardium_bin, "test", path], capture_output=True, text=True, timeout=60, env=env)
    return r.stdout + (f"\n[stderr]\n{r.stderr}" if r.stderr else "")

def tool_ardium_diagnose(params: dict) -> str:
    """Analyze and diagnose Ardium code for syntax, RAII memory rules, and CoreUI integrity."""
    code = params.get("code")
    if not code and "path" in params:
        target = validate_path(params["path"])
        with open(target, "r", encoding="utf-8") as f:
            code = f.read()
    
    if not code:
        raise ValueError("Either 'code' or 'path' must be provided.")
    
    issues = []
    
    # 1. Main Entry Check
    if "fn main()" not in code and "fn main(" not in code:
        issues.append("ℹ️ Note: No 'fn main()' entry function found. Standalone execution expects fn main().")
        
    # 2. Memory Alloc & RAII Check
    alloc_count = len(re.findall(r"\balloc\(", code))
    free_count = len(re.findall(r"\bfree\(", code))
    owned_count = len(re.findall(r"@owned\b", code))
    
    if alloc_count > (free_count + owned_count):
        issues.append(f"⚠️ Memory Warning: Found {alloc_count} 'alloc()' call(s), but only {free_count} 'free()' and {owned_count} '@owned' annotations. Consider '@owned let ptr = alloc(...)' for automatic RAII scope cleanup.")
        
    # 3. CoreUI Stack Balance Check
    vstacks = len(re.findall(r"\bVStack\(", code))
    hstacks = len(re.findall(r"\bHStack\(", code))
    if (vstacks > 0 or hstacks > 0) and "import CoreUI" not in code and "CoreUI" not in code:
        issues.append("💡 Suggestion: CoreUI declarative elements (VStack/HStack) detected. Ensure 'import CoreUI' is declared.")
        
    # 4. Compiler check via arc
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".ar", mode="w", delete=False) as tmp:
        tmp.write(code)
        tmp_name = tmp.name
    try:
        ardium_bin = _find_ardium_bin()
        env = os.environ.copy()
        env["DYLD_LIBRARY_PATH"] = f"/usr/local/ardium/lib:{env.get('DYLD_LIBRARY_PATH', '')}"
        r = subprocess.run([ardium_bin, "build", tmp_name, "-o", tmp_name + ".out"], capture_output=True, text=True, timeout=10, env=env)
        if os.path.exists(tmp_name + ".out"):
            os.remove(tmp_name + ".out")
        if r.returncode != 0:
            syntax_err = r.stderr or r.stdout
            issues.append(f"❌ Compiler Error / Diagnostic:\n{syntax_err.strip()}")
    except Exception as e:
        issues.append(f"⚠️ Compiler check notice: {str(e)}")
    finally:
        if os.path.exists(tmp_name):
            os.remove(tmp_name)
            
    if not issues:
        return "✅ Ardium Diagnostic Passed: Clean syntax, RAII memory safely managed, CoreUI valid."
    return "🔍 Ardium Diagnostics Summary:\n" + "\n".join(issues)

# ============================================================
# Dotmini Computer Use Tools (MicroCode Native)
# ============================================================

def _get_computer_use_engine():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        from tools.computer_use_engine import MicroCodeComputerUse
        return MicroCodeComputerUse()
    except Exception as e:
        raise RuntimeError(f"Failed to initialize MicroCode Computer Use engine: {e}")

def tool_computer_use_inspect(args: dict) -> str:
    engine = _get_computer_use_engine()
    elements = engine.inspect_elements()
    query = args.get("query")
    role = args.get("role")
    if query:
        q = query.lower()
        elements = [e for e in elements if q in e["label"].lower() or q in e["role"].lower()]
    if role:
        r = role.lower()
        elements = [e for e in elements if r in e["role"].lower()]
    return json.dumps(elements, indent=2)

def tool_computer_use_click(args: dict) -> str:
    engine = _get_computer_use_engine()
    target = args.get("target")
    x = args.get("x")
    y = args.get("y")
    click_count = args.get("click_count", 1)
    if target:
        res = engine.click_element(target, role=args.get("role"), click_count=click_count)
        return json.dumps(res, indent=2)
    elif x is not None and y is not None:
        engine.mouse_click(float(x), float(y), click_count=click_count)
        return json.dumps({"success": True, "clicked_at": {"x": float(x), "y": float(y)}}, indent=2)
    else:
        raise ValueError("Must provide either 'target' (label) or 'x' and 'y'")

def tool_computer_use_type(args: dict) -> str:
    engine = _get_computer_use_engine()
    text = args.get("text", "")
    press_enter = args.get("press_enter", False)
    engine.type_text(text, press_enter=press_enter)
    return json.dumps({"success": True, "typed_length": len(text)})

def tool_computer_use_shortcut(args: dict) -> str:
    engine = _get_computer_use_engine()
    modifiers = args.get("modifiers", [])
    key = args.get("key", "")
    engine.send_shortcut(modifiers, key)
    return json.dumps({"success": True, "shortcut": f"{'+'.join(modifiers)}+{key}"})

def tool_computer_use_capture(args: dict) -> str:
    engine = _get_computer_use_engine()
    output_path = args.get("output_path", "/tmp/microcode_screenshot.png")
    res = engine.capture_screenshot(output_path)
    return json.dumps({"success": True, "path": res})

def tool_computer_use_live_test(args: dict) -> str:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from tools.computer_use_engine import MicroCodeComputerUse
    engine = MicroCodeComputerUse()
    art_dir = "/Users/dotmini/.gemini/antigravity/brain/197fe973-60a3-4cf1-b2bf-10645e78f063"
    s0 = engine.capture_screenshot(f"{art_dir}/live_step0_initial.png")
    engine.click_element("Clear Outputs")
    time.sleep(1.0)
    s1 = engine.capture_screenshot(f"{art_dir}/live_step1_cleared.png")
    try:
        engine.click_element("Play")
    except Exception:
        engine.send_shortcut(["cmd"], "return")
    time.sleep(3.5)
    s2 = engine.capture_screenshot(f"{art_dir}/live_step2_executed.png")
    return json.dumps({
        "status": "success",
        "initial": s0,
        "cleared": s1,
        "executed": s2
    }, indent=2)
def tool_device_list(args: dict) -> str:
    """List connected Android devices (physical & emulator), AVDs, and iOS Simulators."""
    devices = []
    
    # 1. Check Android devices via adb
    adb_path = os.environ.get("ADB_PATH", "adb")
    try:
        res = subprocess.run([adb_path, "devices", "-l"], capture_output=True, text=True, timeout=5)
        if res.returncode == 0:
            lines = res.stdout.strip().split("\n")[1:]
            for line in lines:
                if not line.strip(): continue
                parts = line.split()
                if len(parts) >= 2 and parts[1] == "device":
                    serial = parts[0]
                    is_emu = serial.startswith("emulator-")
                    model = "Unknown"
                    for p in parts[2:]:
                        if p.startswith("model:"): model = p.split(":")[1]
                    devices.append({
                        "id": serial,
                        "platform": "Android",
                        "type": "Emulator" if is_emu else "Physical",
                        "name": f"{model} ({serial})",
                        "state": "Connected"
                    })
    except Exception as e:
        pass

    # 2. Check Android AVDs
    emulator_path = os.environ.get("EMULATOR_PATH", "emulator")
    try:
        res = subprocess.run([emulator_path, "-list-avds"], capture_output=True, text=True, timeout=5)
        if res.returncode == 0:
            for avd in res.stdout.strip().split("\n"):
                avd = avd.strip()
                if avd:
                    # Check if already listed as running
                    devices.append({
                        "id": f"avd:{avd}",
                        "platform": "Android",
                        "type": "AVD (Configured)",
                        "name": avd,
                        "state": "Available"
                    })
    except Exception:
        pass

    # 3. Check iOS Simulators via xcrun simctl
    try:
        res = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"], capture_output=True, text=True, timeout=5)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            for runtime, dev_list in data.get("devices", {}).items():
                for dev in dev_list:
                    if dev.get("isAvailable", False):
                        devices.append({
                            "id": dev.get("udid"),
                            "platform": "iOS",
                            "type": "Simulator",
                            "name": f"{dev.get('name')} ({runtime.split('.')[-1]})",
                            "state": dev.get("state")
                        })
    except Exception:
        pass

    return json.dumps({"devices": devices, "count": len(devices)}, indent=2)

def tool_device_interact(args: dict) -> str:
    """Interact with a device: tap, swipe, text, key, screenshot."""
    action = args.get("action", "").lower()
    device_id = args.get("device_id")
    
    adb_path = os.environ.get("ADB_PATH", "adb")
    
    if action == "tap":
        x = args.get("x")
        y = args.get("y")
        if x is None or y is None: raise ValueError("Tap requires 'x' and 'y'")
        cmd = [adb_path] + (["-s", device_id] if device_id else []) + ["shell", "input", "tap", str(int(x)), str(int(y))]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return json.dumps({"success": res.returncode == 0, "action": "tap", "coords": [x, y], "output": res.stdout})

    elif action == "swipe":
        x1, y1 = args.get("x"), args.get("y")
        x2, y2 = args.get("x2"), args.get("y2")
        dur = args.get("duration", 200)
        if None in (x1, y1, x2, y2): raise ValueError("Swipe requires x, y, x2, y2")
        cmd = [adb_path] + (["-s", device_id] if device_id else []) + ["shell", "input", "swipe", str(int(x1)), str(int(y1)), str(int(x2)), str(int(y2)), str(int(dur))]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return json.dumps({"success": res.returncode == 0, "action": "swipe", "output": res.stdout})

    elif action == "text":
        text = args.get("text", "")
        escaped = text.replace(" ", "%s").replace("\n", "%s")
        cmd = [adb_path] + (["-s", device_id] if device_id else []) + ["shell", "input", "text", escaped]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return json.dumps({"success": res.returncode == 0, "action": "text", "typed": text, "output": res.stdout})

    elif action == "key":
        key = str(args.get("key", "3"))
        key_map = {"HOME": "3", "BACK": "4", "ENTER": "66", "POWER": "26", "RECENT": "187"}
        code = key_map.get(key.upper(), key)
        cmd = [adb_path] + (["-s", device_id] if device_id else []) + ["shell", "input", "keyevent", code]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return json.dumps({"success": res.returncode == 0, "action": "key", "keycode": code, "output": res.stdout})

    elif action == "screenshot":
        out_path = args.get("output_path", f"/tmp/device_{int(time.time())}.png")
        if device_id and len(device_id) == 36 and "-" in device_id: # likely iOS UDID
            cmd = ["xcrun", "simctl", "io", device_id, "screenshot", out_path]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        else:
            cmd = [adb_path] + (["-s", device_id] if device_id else []) + ["exec-out", "screencap", "-p"]
            with open(out_path, "wb") as f:
                res = subprocess.run(cmd, stdout=f, stderr=subprocess.PIPE, timeout=15)
        return json.dumps({"success": res.returncode == 0, "action": "screenshot", "path": out_path})

    else:
        raise ValueError(f"Unknown action: {action}. Must be tap, swipe, text, key, or screenshot")

def tool_device_app_manage(args: dict) -> str:
    """Install, launch, or force-stop an application on device."""
    op = args.get("operation", "").lower()
    device_id = args.get("device_id")
    identifier = args.get("identifier")
    package_path = args.get("package_path")
    adb_path = os.environ.get("ADB_PATH", "adb")

    if op == "launch":
        if not identifier: raise ValueError("launch requires 'identifier' (package or bundle ID)")
        if device_id and len(device_id) == 36 and "-" in device_id:
            cmd = ["xcrun", "simctl", "launch", device_id, identifier]
        else:
            cmd = [adb_path] + (["-s", device_id] if device_id else []) + ["shell", "monkey", "-p", identifier, "-c", "android.intent.category.LAUNCHER", "1"]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        return json.dumps({"success": res.returncode == 0, "operation": "launch", "output": res.stdout + res.stderr})

    elif op == "stop":
        if not identifier: raise ValueError("stop requires 'identifier'")
        if device_id and len(device_id) == 36 and "-" in device_id:
            cmd = ["xcrun", "simctl", "terminate", device_id, identifier]
        else:
            cmd = [adb_path] + (["-s", device_id] if device_id else []) + ["shell", "am", "force-stop", identifier]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return json.dumps({"success": res.returncode == 0, "operation": "stop", "output": res.stdout + res.stderr})

    elif op == "install":
        if not package_path: raise ValueError("install requires 'package_path'")
        if device_id and len(device_id) == 36 and "-" in device_id:
            cmd = ["xcrun", "simctl", "install", device_id, package_path]
        else:
            cmd = [adb_path] + (["-s", device_id] if device_id else []) + ["install", "-r", "-t", package_path]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=45)
        return json.dumps({"success": res.returncode == 0, "operation": "install", "output": res.stdout + res.stderr})

    else:
        raise ValueError(f"Unknown operation: {op}. Must be launch, stop, or install")

def tool_adb_execute(args: dict) -> str:
    """Execute raw ADB shell command on connected device."""
    command = args.get("command")
    device_id = args.get("device_id")
    if not command: raise ValueError("command is required")
    adb_path = os.environ.get("ADB_PATH", "adb")
    cmd = [adb_path] + (["-s", device_id] if device_id else []) + ["shell", command]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    return json.dumps({
        "returncode": res.returncode,
        "stdout": res.stdout,
        "stderr": res.stderr
    })

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
        "description": "Run code instantly without creating a cell (playground/scratch mode). Supports Ardium (.ar), Python, JS, Swift, Rust, Go, C, C++, Java, Ruby, Bash.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "language": {"type": "string", "description": "Language: ardium, python, javascript, swift, rust, go, c, cpp, java, ruby, bash"},
                "code": {"type": "string", "description": "Source code to execute"},
                "cwd": {"type": "string", "description": "Working directory (optional)"}
            },
            "required": ["code"]
        },
        "handler": tool_playground_run
    },
    "ardium_run": {
        "description": "Execute Ardium (.ar) source code or file directly with output and exit code.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "code": {"type": "string", "description": "Ardium source code to execute"},
                "path": {"type": "string", "description": "Path to .ar file to execute (optional if code is provided)"},
                "cwd": {"type": "string", "description": "Working directory (optional)"}
            }
        },
        "handler": tool_ardium_run
    },
    "ardium_compile": {
        "description": "Compile an Ardium source file (.ar) into a standalone native binary.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Path to the .ar source file to compile"},
                "output": {"type": "string", "description": "Destination path for the compiled executable (optional)"}
            },
            "required": ["path"]
        },
        "handler": tool_ardium_compile
    },
    "ardium_test": {
        "description": "Run Ardium unit/integration tests marked with @test in a project or file.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Project directory or .ar file containing tests"}
            }
        },
        "handler": tool_ardium_test
    },
    "ardium_diagnose": {
        "description": "Analyze Ardium code for syntax correctness, RAII memory safety (@owned, alloc/free), and CoreUI layout rules.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "code": {"type": "string", "description": "Ardium source code to diagnose"},
                "path": {"type": "string", "description": "Path to .ar file to diagnose (optional if code is provided)"}
            }
        },
        "handler": tool_ardium_diagnose
    },
    # --- Dotmini Computer Use Tools ---
    "computer_use_inspect": {
        "description": "Inspect all interactive UI elements in the MicroCode native macOS window (buttons, menus, cells, editors) with bounding boxes and coordinates.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Filter by element title or label substring"},
                "role": {"type": "string", "description": "Filter by AX role (e.g. AXButton, AXMenuButton)"}
            }
        },
        "handler": tool_computer_use_inspect
    },
    "computer_use_click": {
        "description": "Simulate physical human mouse click on a MicroCode UI element by label/title (e.g. 'Clear Outputs', 'Play', 'Code') or explicit screen coordinates (x, y).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "target": {"type": "string", "description": "Target UI element title or label"},
                "role": {"type": "string", "description": "Optional AX role filter"},
                "x": {"type": "number", "description": "Target screen X coordinate"},
                "y": {"type": "number", "description": "Target screen Y coordinate"},
                "click_count": {"type": "integer", "description": "1 for single click, 2 for double click"}
            }
        },
        "handler": tool_computer_use_click
    },
    "computer_use_type": {
        "description": "Type text directly into the focused editor or cell with natural human typing cadence.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Text or code to type"},
                "press_enter": {"type": "boolean", "description": "Whether to hit Enter after typing"}
            },
            "required": ["text"]
        },
        "handler": tool_computer_use_type
    },
    "computer_use_shortcut": {
        "description": "Send native macOS keyboard shortcuts to MicroCode (e.g. Cmd+Return to run cell, Cmd+K, Cmd+S).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "modifiers": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Modifiers: cmd, shift, option, ctrl"
                },
                "key": {"type": "string", "description": "Key name: return, space, escape, k, s, etc."}
            },
            "required": ["modifiers", "key"]
        },
        "handler": tool_computer_use_shortcut
    },
    "computer_use_capture": {
        "description": "Capture a crystal clear real-time screenshot of the MicroCode native window.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "output_path": {"type": "string", "description": "Destination file path for PNG screenshot"}
            }
        },
        "handler": tool_computer_use_capture
    },
    "computer_use_live_test": {
        "description": "Execute a full real-time human simulation test on the running MicroCode notebook (captures before, clicks Clear Outputs, executes Play, and captures rendered output).",
        "inputSchema": {
            "type": "object",
            "properties": {}
        },
        "handler": tool_computer_use_live_test
    },
    # --- Device & Hardware Automation Tools ---
    "device_list": {
        "description": "List connected Android physical devices, running emulators, configured AVDs, and iOS Simulators.",
        "inputSchema": {
            "type": "object",
            "properties": {}
        },
        "handler": tool_device_list
    },
    "device_interact": {
        "description": "Interact with an Android device/emulator or iOS simulator: tap, swipe, text, key, screenshot.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "action": {"type": "string", "description": "tap | swipe | text | key | screenshot"},
                "device_id": {"type": "string", "description": "Target device serial or UDID"},
                "x": {"type": "number", "description": "X coordinate for tap or swipe start"},
                "y": {"type": "number", "description": "Y coordinate for tap or swipe start"},
                "x2": {"type": "number", "description": "X coordinate for swipe end"},
                "y2": {"type": "number", "description": "Y coordinate for swipe end"},
                "duration": {"type": "integer", "description": "Swipe duration in ms (default 200)"},
                "text": {"type": "string", "description": "Text to type"},
                "key": {"type": "string", "description": "Key code or name (HOME, BACK, ENTER, POWER, RECENT)"},
                "output_path": {"type": "string", "description": "Output path for screenshot"}
            },
            "required": ["action"]
        },
        "handler": tool_device_interact
    },
    "device_app_manage": {
        "description": "Launch, stop, or install an application on target Android or iOS device.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "operation": {"type": "string", "description": "launch | stop | install"},
                "device_id": {"type": "string", "description": "Target device serial or UDID"},
                "identifier": {"type": "string", "description": "Package name (Android) or Bundle ID (iOS)"},
                "package_path": {"type": "string", "description": "Path to .apk or .app bundle for installation"}
            },
            "required": ["operation"]
        },
        "handler": tool_device_app_manage
    },
    "adb_execute": {
        "description": "Execute raw ADB shell command on connected Android device.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "ADB shell command to run"},
                "device_id": {"type": "string", "description": "Target Android device serial"}
            },
            "required": ["command"]
        },
        "handler": tool_adb_execute
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
