#!/bin/bash
# Agent eval grader regression (real AgentEvalGrader.swift).
set -euo pipefail
cd "$(dirname "$0")/../.."
for d in /Volumes/MAC/CodeTunerBuild /Volumes/MicroCodeBuild; do [ -d "$d" ] && export TMPDIR="$d/tmp" && break; done
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-evalgrader.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
cp Scripts/tests/agent-eval-grader-regression.swift "$out_dir/main.swift"
swiftc MicroCode/Services/AgentCore/AgentEvalGrader.swift "$out_dir/main.swift" -o "$out_dir/agent-eval-grader"
"$out_dir/agent-eval-grader"
