#!/bin/bash
# ============================================================
# MicroCode MCP — Quick Install for Claude Desktop
# ============================================================
# Automatically installs MicroCode as a Claude Desktop extension
# Usage: ./install-mcp.sh [workspace_path]
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MCP_SERVER="$SCRIPT_DIR/mcp-server.py"
WORKSPACE="${1:-$SCRIPT_DIR}"

# Claude Desktop config path
CLAUDE_CONFIG="$HOME/.claude/claude_desktop_config.json"
CLAUDE_DIR="$HOME/.claude"

echo "🔧 MicroCode MCP Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Server:    $MCP_SERVER"
echo "  Workspace: $WORKSPACE"
echo ""

# Make server executable
chmod +x "$MCP_SERVER"

# Create .claude directory if needed
mkdir -p "$CLAUDE_DIR"

# Build the MCP config entry
MCP_ENTRY=$(cat <<EOF
{
  "command": "python3",
  "args": ["$MCP_SERVER"],
  "env": {
    "MICROCODE_WORKSPACE": "$WORKSPACE"
  }
}
EOF
)

# Check if config exists
if [ -f "$CLAUDE_CONFIG" ]; then
    echo "📄 Existing Claude config found. Merging..."
    
    # Check if python3 with json is available
    if command -v python3 &> /dev/null; then
        python3 -c "
import json, sys

config_path = '$CLAUDE_CONFIG'
with open(config_path, 'r') as f:
    config = json.load(f)

if 'mcpServers' not in config:
    config['mcpServers'] = {}

config['mcpServers']['microcode'] = {
    'command': 'python3',
    'args': ['$MCP_SERVER'],
    'env': {
        'MICROCODE_WORKSPACE': '$WORKSPACE'
    }
}

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)

print('✅ Merged microcode into existing Claude config')
"
    else
        echo "⚠️  python3 not found. Please manually add to $CLAUDE_CONFIG:"
        echo "$MCP_ENTRY"
    fi
else
    echo "📝 Creating new Claude config..."
    cat > "$CLAUDE_CONFIG" <<CONFIGEOF
{
  "mcpServers": {
    "microcode": {
      "command": "python3",
      "args": ["$MCP_SERVER"],
      "env": {
        "MICROCODE_WORKSPACE": "$WORKSPACE"
      }
    }
  }
}
CONFIGEOF
    echo "✅ Created $CLAUDE_CONFIG"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ MicroCode MCP installed!"
echo ""
echo "Available tools (14):"
echo "  file_read, file_write, replace_in_file, grep_search,"
echo "  list_directory_tree, shell, git_status, find_symbol,"
echo "  create_directory, rename_file, patch_file,"
echo "  multi_file_read, web_fetch"
echo ""
echo "🔄 Restart Claude Desktop to activate."
echo ""
echo "To connect from other MCP clients, use:"
echo "  python3 $MCP_SERVER"
echo ""
