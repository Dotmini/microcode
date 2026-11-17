#!/bin/bash
# Phase 3a harness regression (real sources: spawn policy, plan mode, freshness guard, untracked snapshot, trace).
set -euo pipefail
cd "$(dirname "$0")/../.."
for d in /Volumes/MAC/CodeTunerBuild /Volumes/MicroCodeBuild; do [ -d "$d" ] && export TMPDIR="$d/tmp" && break; done
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-phase3a.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
# AgentToolTrace's shared instance uses the app's secret redactor; tests inject their own.
cat > "$out_dir/stubs.swift" <<'SWIFT'
enum AgentPrivacyGuard { static func sanitize(_ text: String) -> String { text } }
SWIFT
swiftc -parse-as-library \
  MicroCode/Services/SubAgentSpawnPolicy.swift \
  MicroCode/Services/AgentCore/PlanModePolicy.swift \
  MicroCode/Services/AgentCore/AgentExecutionContext.swift \
  MicroCode/Services/AgentCore/FileFreshnessGuard.swift \
  MicroCode/Services/GitUntrackedSnapshot.swift \
  MicroCode/Services/AgentCore/AgentToolTrace.swift \
  "$out_dir/stubs.swift" \
  Scripts/tests/phase3a-harness-regression.swift \
  -o "$out_dir/phase3a"
"$out_dir/phase3a"
