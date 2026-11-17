#!/bin/bash
# Phase 2 protocol regression: compiles the real MCP/ACP protocol sources with the regression driver.
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ -d "/Volumes/MAC/CodeTunerBuild" ]; then
  export TMPDIR="/Volumes/MAC/CodeTunerBuild/tmp"
elif [ -d "/Volumes/MicroCodeBuild" ]; then
  export TMPDIR="/Volumes/MicroCodeBuild/tmp"
fi
mkdir -p "${TMPDIR:-/tmp}"

out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-phase2.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT

swiftc -parse-as-library \
  MicroCode/Services/MCPProtocolSupport.swift \
  MicroCode/Services/AgentCore/ACPProtocol.swift \
  Scripts/tests/phase2-protocol-regression.swift \
  -o "$out_dir/phase2"
"$out_dir/phase2"
