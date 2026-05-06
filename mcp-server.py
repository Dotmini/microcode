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
SERVER_VERSION = "1.3.2"
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
    req = urllib.request.Request(url, headers={"User-Agent": "MicroCode-MCP/1.0"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        content = resp.read().decode("utf-8", errors="replace")
    if len(content) > 5000:
        return content[:5000] + "\n... (truncated)"
    return content

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
    }
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
