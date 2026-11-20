#!/bin/bash
# Managed task.md regression (real AgentTaskFile.swift): no generic checklist ritual.
set -euo pipefail
cd "$(dirname "$0")/../.."
for d in /Volumes/MAC/CodeTunerBuild /Volumes/MicroCodeBuild; do [ -d "$d" ] && export TMPDIR="$d/tmp" && break; done
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-taskfile.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
cp Scripts/tests/agent-task-file-regression.swift "$out_dir/main.swift"
swiftc MicroCode/Services/AgentCore/AgentTaskFile.swift "$out_dir/main.swift" -o "$out_dir/agent-task-file"
"$out_dir/agent-task-file"
