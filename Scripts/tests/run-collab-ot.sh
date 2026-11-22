#!/bin/bash
# ot1 real-time co-editing regression (real CollabTextOperation.swift): algebra, surrogate-safe diff, host log,
# and randomized multi-client convergence.
set -euo pipefail
cd "$(dirname "$0")/../.."
for d in /Volumes/MAC/CodeTunerBuild /Volumes/MicroCodeBuild; do [ -d "$d" ] && export TMPDIR="$d/tmp" && break; done
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-collab-ot.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
cp Scripts/tests/collab-ot-regression.swift "$out_dir/main.swift"
swiftc -O MicroCode/Services/CollabTextOperation.swift "$out_dir/main.swift" -o "$out_dir/collab-ot"
"$out_dir/collab-ot"
