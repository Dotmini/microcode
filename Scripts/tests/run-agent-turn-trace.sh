#!/bin/bash
# Agent turn trace regression (real AgentTurnTrace.swift): per-message provider/model + harness interventions.
set -euo pipefail
cd "$(dirname "$0")/../.."
for d in /Volumes/MAC/CodeTunerBuild /Volumes/MicroCodeBuild; do [ -d "$d" ] && export TMPDIR="$d/tmp" && break; done
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-turntrace.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
cp Scripts/tests/agent-turn-trace-regression.swift "$out_dir/main.swift"
swiftc MicroCode/Services/AgentCore/AgentTurnTrace.swift "$out_dir/main.swift" -o "$out_dir/agent-turn-trace"
"$out_dir/agent-turn-trace"
