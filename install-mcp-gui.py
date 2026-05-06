#!/usr/bin/env python3
"""
MicroCode MCP — GUI Installer (macOS)
====================================
One-click installer for Claude Desktop, Cursor, Windsurf, and any MCP client.
Double-click to launch → Select workspace → Click Install → Done.

Copyright © 2025 SPU AI CLUB — Dotmini Software
"""

import os
import sys
import json
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from pathlib import Path
import subprocess

# ============================================================
# Config
# ============================================================

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MCP_SERVER = os.path.join(SCRIPT_DIR, "mcp-server.py")

CLIENTS = {
    "claude": {
        "name": "Claude Desktop",
        "icon": "🟠",
        "config_path": os.path.expanduser("~/Library/Application Support/Claude/claude_desktop_config.json"),
        "config_dir": os.path.expanduser("~/Library/Application Support/Claude"),
        "key": "mcpServers",
    },
    "cursor": {
        "name": "Cursor",
        "icon": "🟣",
        "config_path": os.path.expanduser("~/.cursor/mcp.json"),
        "config_dir": os.path.expanduser("~/.cursor"),
        "key": "mcpServers",
    },
    "windsurf": {
        "name": "Windsurf",
        "icon": "🔵",
        "config_path": os.path.expanduser("~/.codeium/windsurf/mcp_config.json"),
        "config_dir": os.path.expanduser("~/.codeium/windsurf"),
        "key": "mcpServers",
    },
    "vscode": {
        "name": "VS Code (Copilot)",
        "icon": "🟢",
        "config_path": os.path.expanduser("~/.vscode/mcp.json"),
        "config_dir": os.path.expanduser("~/.vscode"),
        "key": "servers",
    },
}

# ============================================================
# Installer Logic
# ============================================================

def check_installed(client_id: str) -> bool:
    """Check if MicroCode MCP is already installed for a client."""
    client = CLIENTS[client_id]
    if not os.path.exists(client["config_path"]):
        return False
    try:
        with open(client["config_path"], "r") as f:
            config = json.load(f)
        servers = config.get(client["key"], {})
        return "microcode" in servers
    except:
        return False

def install_for_client(client_id: str, workspace: str) -> str:
    """Install MicroCode MCP for a specific client. Returns status message."""
    client = CLIENTS[client_id]
    
    # Ensure config dir exists
    os.makedirs(client["config_dir"], exist_ok=True)
    
    # Load or create config
    config = {}
    if os.path.exists(client["config_path"]):
        try:
            with open(client["config_path"], "r") as f:
                config = json.load(f)
        except:
            config = {}
    
    # Add MCP server entry
    if client["key"] not in config:
        config[client["key"]] = {}
    
    config[client["key"]]["microcode"] = {
        "command": "python3",
        "args": [MCP_SERVER],
        "env": {
            "MICROCODE_WORKSPACE": workspace
        }
    }
    
    # Write config
    with open(client["config_path"], "w") as f:
        json.dump(config, f, indent=2)
    
    # Make server executable
    os.chmod(MCP_SERVER, 0o755)
    
    return f"✅ Installed for {client['name']}"

def uninstall_for_client(client_id: str) -> str:
    """Remove MicroCode MCP from a specific client."""
    client = CLIENTS[client_id]
    if not os.path.exists(client["config_path"]):
        return "Not installed"
    
    try:
        with open(client["config_path"], "r") as f:
            config = json.load(f)
        
        servers = config.get(client["key"], {})
        if "microcode" in servers:
            del servers[client["key"]]["microcode"]
            with open(client["config_path"], "w") as f:
                json.dump(config, f, indent=2)
            return f"🗑 Removed from {client['name']}"
        return "Not installed"
    except:
        return "Error reading config"

# ============================================================
# GUI Application
# ============================================================

class MCPInstallerApp:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("MicroCode MCP Installer")
        self.root.geometry("580x620")
        self.root.resizable(False, False)
        
        # macOS dark mode detection
        try:
            result = subprocess.run(
                ["defaults", "read", "-g", "AppleInterfaceStyle"],
                capture_output=True, text=True
            )
            is_dark = "Dark" in result.stdout
        except:
            is_dark = True
        
        bg = "#1e1e1e" if is_dark else "#f5f5f5"
        fg = "#ffffff" if is_dark else "#1a1a1a"
        card_bg = "#2d2d2d" if is_dark else "#ffffff"
        accent = "#007AFF"
        green = "#34C759"
        subtle = "#888888"
        
        self.root.configure(bg=bg)
        self.workspace_var = tk.StringVar(value=SCRIPT_DIR)
        self.client_vars = {}
        
        # Style
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("Title.TLabel", font=("SF Pro Display", 20, "bold"), background=bg, foreground=fg)
        style.configure("Sub.TLabel", font=("SF Pro Text", 11), background=bg, foreground=subtle)
        style.configure("Card.TFrame", background=card_bg)
        style.configure("Normal.TLabel", font=("SF Pro Text", 12), background=card_bg, foreground=fg)
        style.configure("Status.TLabel", font=("SF Pro Text", 10), background=card_bg, foreground=green)
        style.configure("Icon.TLabel", font=("", 22), background=card_bg)
        style.configure("Install.TButton", font=("SF Pro Text", 13, "bold"))
        style.configure("Browse.TButton", font=("SF Pro Text", 11))
        style.configure("Section.TLabel", font=("SF Pro Text", 10, "bold"), background=bg, foreground=subtle)
        style.configure("Path.TLabel", font=("SF Mono", 10), background=bg, foreground=accent)
        
        # === Header ===
        header = tk.Frame(self.root, bg=bg)
        header.pack(fill="x", padx=24, pady=(20, 4))
        
        tk.Label(header, text="⚡", font=("", 32), bg=bg).pack(side="left", padx=(0, 10))
        
        title_frame = tk.Frame(header, bg=bg)
        title_frame.pack(side="left")
        tk.Label(title_frame, text="MicroCode MCP", font=("SF Pro Display", 20, "bold"), bg=bg, fg=fg).pack(anchor="w")
        tk.Label(title_frame, text="One-click AI tool integration • 21 tools • 12 languages", font=("SF Pro Text", 11), bg=bg, fg=subtle).pack(anchor="w")
        
        # Version badge
        ver_frame = tk.Frame(header, bg=accent, padx=8, pady=2)
        ver_frame.pack(side="right")
        tk.Label(ver_frame, text="v2.0", font=("SF Mono", 10, "bold"), bg=accent, fg="#fff").pack()
        
        # === Workspace Section ===
        tk.Label(self.root, text="WORKSPACE", font=("SF Pro Text", 10, "bold"), bg=bg, fg=subtle).pack(anchor="w", padx=24, pady=(16, 4))
        
        ws_frame = tk.Frame(self.root, bg=card_bg, highlightbackground="#444", highlightthickness=1)
        ws_frame.pack(fill="x", padx=24, pady=(0, 12))
        
        ws_inner = tk.Frame(ws_frame, bg=card_bg)
        ws_inner.pack(fill="x", padx=12, pady=10)
        
        tk.Label(ws_inner, text="📁", font=("", 16), bg=card_bg).pack(side="left", padx=(0, 8))
        
        path_entry = tk.Entry(ws_inner, textvariable=self.workspace_var, font=("SF Mono", 11), bg="#383838" if is_dark else "#eee", fg=fg, insertbackground=fg, bd=0, highlightthickness=0)
        path_entry.pack(side="left", fill="x", expand=True, ipady=4, padx=(0, 8))
        
        browse_btn = tk.Button(ws_inner, text="Browse", font=("SF Pro Text", 11), command=self.browse_workspace, bg=accent, fg="#fff", bd=0, padx=12, pady=4, activebackground="#0056b3")
        browse_btn.pack(side="right")
        
        # === Clients Section ===
        tk.Label(self.root, text="AI CLIENTS", font=("SF Pro Text", 10, "bold"), bg=bg, fg=subtle).pack(anchor="w", padx=24, pady=(8, 4))
        
        clients_frame = tk.Frame(self.root, bg=bg)
        clients_frame.pack(fill="x", padx=24, pady=(0, 12))
        
        for client_id, client in CLIENTS.items():
            installed = check_installed(client_id)
            var = tk.BooleanVar(value=True)
            self.client_vars[client_id] = var
            
            card = tk.Frame(clients_frame, bg=card_bg, highlightbackground="#444" if is_dark else "#ddd", highlightthickness=1)
            card.pack(fill="x", pady=3)
            
            inner = tk.Frame(card, bg=card_bg)
            inner.pack(fill="x", padx=12, pady=8)
            
            # Checkbox
            cb = tk.Checkbutton(inner, variable=var, bg=card_bg, activebackground=card_bg, selectcolor="#383838" if is_dark else "#eee")
            cb.pack(side="left", padx=(0, 4))
            
            # Icon
            tk.Label(inner, text=client["icon"], font=("", 18), bg=card_bg).pack(side="left", padx=(0, 8))
            
            # Name + path
            info = tk.Frame(inner, bg=card_bg)
            info.pack(side="left", fill="x", expand=True)
            tk.Label(info, text=client["name"], font=("SF Pro Text", 13, "bold"), bg=card_bg, fg=fg).pack(anchor="w")
            
            short_path = client["config_path"].replace(os.path.expanduser("~"), "~")
            tk.Label(info, text=short_path, font=("SF Mono", 9), bg=card_bg, fg=subtle).pack(anchor="w")
            
            # Status
            status_text = "✅ Installed" if installed else "⬜ Not installed"
            status_color = green if installed else subtle
            tk.Label(inner, text=status_text, font=("SF Pro Text", 10), bg=card_bg, fg=status_color).pack(side="right")
        
        # === Tools Info ===
        tk.Label(self.root, text="INCLUDED TOOLS (21)", font=("SF Pro Text", 10, "bold"), bg=bg, fg=subtle).pack(anchor="w", padx=24, pady=(8, 4))
        
        tools_frame = tk.Frame(self.root, bg=card_bg, highlightbackground="#444" if is_dark else "#ddd", highlightthickness=1)
        tools_frame.pack(fill="x", padx=24, pady=(0, 16))
        
        tools_text = "📂 file_read • file_write • replace_in_file • patch_file • multi_file_read\n🔍 grep_search • find_symbol • list_directory_tree • file_search\n⚡ shell • git_status • git_diff • create_directory • rename_file • web_fetch\n🧪 cell_create • cell_read • cell_update • cell_delete • cell_run\n🎮 cell_list • playground_run"
        tk.Label(tools_frame, text=tools_text, font=("SF Mono", 9), bg=card_bg, fg=fg, justify="left", wraplength=520).pack(padx=12, pady=10, anchor="w")
        
        # === Install Button ===
        btn_frame = tk.Frame(self.root, bg=bg)
        btn_frame.pack(fill="x", padx=24, pady=(0, 8))
        
        install_btn = tk.Button(btn_frame, text="⚡  Install MicroCode MCP", font=("SF Pro Display", 14, "bold"), command=self.install_all, bg=accent, fg="#ffffff", bd=0, pady=10, activebackground="#0056b3", cursor="hand2")
        install_btn.pack(fill="x")
        
        # Footer
        tk.Label(self.root, text="After installing, restart the AI client to activate • SPU AI CLUB — Dotmini Software", font=("SF Pro Text", 9), bg=bg, fg="#555").pack(pady=(4, 12))
    
    def browse_workspace(self):
        path = filedialog.askdirectory(title="Select Workspace Folder", initialdir=self.workspace_var.get())
        if path:
            self.workspace_var.set(path)
    
    def install_all(self):
        workspace = self.workspace_var.get()
        if not os.path.isdir(workspace):
            messagebox.showerror("Error", f"Workspace not found:\n{workspace}")
            return
        
        results = []
        for client_id, var in self.client_vars.items():
            if var.get():
                try:
                    msg = install_for_client(client_id, workspace)
                    results.append(msg)
                except Exception as e:
                    results.append(f"❌ {CLIENTS[client_id]['name']}: {e}")
        
        if not results:
            messagebox.showwarning("No clients selected", "Please select at least one AI client.")
            return
        
        summary = "\n".join(results)
        summary += "\n\n🔄 Restart your AI clients to activate MicroCode MCP."
        messagebox.showinfo("Installation Complete", summary)
        self.root.destroy()
    
    def run(self):
        self.root.mainloop()

# ============================================================
# Main
# ============================================================

if __name__ == "__main__":
    app = MCPInstallerApp()
    app.run()
