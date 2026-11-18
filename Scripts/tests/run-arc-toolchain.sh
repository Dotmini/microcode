#!/bin/bash
# Arc toolchain resolution regression (real ArcToolchain.swift).
set -euo pipefail
cd "$(dirname "$0")/../.."
for d in /Volumes/MAC/CodeTunerBuild /Volumes/MicroCodeBuild; do [ -d "$d" ] && export TMPDIR="$d/tmp" && break; done
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-arc-toolchain.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
# The regression is top-level code, which swiftc only allows in main.swift.
cp Scripts/tests/arc-toolchain-regression.swift "$out_dir/main.swift"
swiftc \
  MicroCode/Services/ArcToolchain.swift \
  "$out_dir/main.swift" \
  -o "$out_dir/arc-toolchain"
"$out_dir/arc-toolchain"
