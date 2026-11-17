#!/bin/bash
# Phase 2b-2: ACP session lifecycle regression (real ACPProtocol.swift + ACPSessionStore.swift).
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ -d "/Volumes/MAC/CodeTunerBuild" ]; then
  export TMPDIR="/Volumes/MAC/CodeTunerBuild/tmp"
elif [ -d "/Volumes/MicroCodeBuild" ]; then
  export TMPDIR="/Volumes/MicroCodeBuild/tmp"
fi
mkdir -p "${TMPDIR:-/tmp}"

out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-phase2b-acp.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT

swiftc -parse-as-library \
  MicroCode/Services/AgentCore/ACPProtocol.swift \
  MicroCode/Services/AgentCore/ACPSessionStore.swift \
  Scripts/tests/phase2b-acp-regression.swift \
  -o "$out_dir/phase2b-acp"
"$out_dir/phase2b-acp"
