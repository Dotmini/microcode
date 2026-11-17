#!/bin/bash
# Phase 0 security regression: compiles the real production sources with the regression driver.
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ -d "/Volumes/MAC/CodeTunerBuild" ]; then
  export TMPDIR="/Volumes/MAC/CodeTunerBuild/tmp"
elif [ -d "/Volumes/MicroCodeBuild" ]; then
  export TMPDIR="/Volumes/MicroCodeBuild/tmp"
fi
mkdir -p "${TMPDIR:-/tmp}"

out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-phase0.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT

swiftc -parse-as-library \
  MicroCode/Models/ToolApprovalModels.swift \
  MicroCode/Services/WorkspaceTrustService.swift \
  MicroCode/Services/AgentCore/ACPProtocol.swift \
  Scripts/tests/phase0-security-regression.swift \
  -o "$out_dir/phase0"
"$out_dir/phase0"
