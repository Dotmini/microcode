#!/bin/bash
# Live check: ArdiumRunner + ArcToolchain with the `arc` installed on this Mac (skips when none is installed).
set -euo pipefail
cd "$(dirname "$0")/../.."
for d in /Volumes/MAC/CodeTunerBuild /Volumes/MicroCodeBuild; do [ -d "$d" ] && export TMPDIR="$d/tmp" && break; done
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-arc-runner.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
cp Scripts/tests/arc-runner-live.swift "$out_dir/main.swift"
swiftc MicroCode/Services/ArcToolchain.swift MicroCode/Services/ArdiumRunner.swift "$out_dir/main.swift" -o "$out_dir/arc-runner-live"
"$out_dir/arc-runner-live"
