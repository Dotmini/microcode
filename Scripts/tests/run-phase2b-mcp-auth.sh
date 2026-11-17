#!/bin/bash
# Phase 2b: MCP OAuth 2.1 regression against a local mock authorization + resource server.
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ -d "/Volumes/MAC/CodeTunerBuild" ]; then
  export TMPDIR="/Volumes/MAC/CodeTunerBuild/tmp"
elif [ -d "/Volumes/MicroCodeBuild" ]; then
  export TMPDIR="/Volumes/MicroCodeBuild/tmp"
fi
mkdir -p "${TMPDIR:-/tmp}"

out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-phase2b.XXXXXX")
export MOCK_PORT="${MOCK_PORT:-18999}"
python3 -I Scripts/tests/fixtures/mcp_oauth_mock.py "$MOCK_PORT" > "$out_dir/mock.log" 2>&1 &
mock_pid=$!
trap 'kill $mock_pid 2>/dev/null || true; wait $mock_pid 2>/dev/null || true; rm -rf "$out_dir"' EXIT

swiftc -parse-as-library \
  MicroCode/Services/MCPAuth.swift \
  Scripts/tests/phase2b-mcp-auth-regression.swift \
  -o "$out_dir/phase2b"

for _ in $(seq 1 50); do grep -q READY "$out_dir/mock.log" 2>/dev/null && break; sleep 0.1; done
"$out_dir/phase2b"
