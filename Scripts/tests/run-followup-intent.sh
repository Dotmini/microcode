#!/bin/bash
# Follow-up intent regression (real FollowUpIntent.swift): "run"/"ไหน"/"ต่อ" after earlier work.
set -euo pipefail
cd "$(dirname "$0")/../.."
for d in /Volumes/MAC/CodeTunerBuild /Volumes/MicroCodeBuild; do [ -d "$d" ] && export TMPDIR="$d/tmp" && break; done
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-followup.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
cp Scripts/tests/followup-intent-regression.swift "$out_dir/main.swift"
swiftc MicroCode/Services/AgentCore/FollowUpIntent.swift "$out_dir/main.swift" -o "$out_dir/followup-intent"
"$out_dir/followup-intent"
