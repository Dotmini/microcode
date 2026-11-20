#!/bin/bash
# Text-bridge context budget + transcript rendering regression (real AIStreamPrimitives.swift).
set -euo pipefail
cd "$(dirname "$0")/../.."
for d in /Volumes/MAC/CodeTunerBuild /Volumes/MicroCodeBuild; do [ -d "$d" ] && export TMPDIR="$d/tmp" && break; done
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-text-bridge.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
# The regression is top-level code, which swiftc only allows in main.swift.
cp Scripts/tests/text-bridge-regression.swift "$out_dir/main.swift"
swiftc \
  MicroCode/Services/AIStreamPrimitives.swift \
  "$out_dir/main.swift" \
  -o "$out_dir/text-bridge"
"$out_dir/text-bridge"
