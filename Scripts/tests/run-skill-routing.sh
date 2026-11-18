#!/bin/bash
# Phase 3c skill routing regression (real SkillRouter.swift). Pass --live to also report routing on this Mac's installed skills.
set -euo pipefail
cd "$(dirname "$0")/../.."
for d in /Volumes/MAC/CodeTunerBuild /Volumes/MicroCodeBuild; do [ -d "$d" ] && export TMPDIR="$d/tmp" && break; done
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-skill-routing.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
# The regression is top-level code, which swiftc only allows in main.swift.
cp Scripts/tests/skill-routing-regression.swift "$out_dir/main.swift"
swiftc \
  MicroCode/Services/AgentCore/SkillRouter.swift \
  "$out_dir/main.swift" \
  -o "$out_dir/skill-routing"
"$out_dir/skill-routing" "$@"
