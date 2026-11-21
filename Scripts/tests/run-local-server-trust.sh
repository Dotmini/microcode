#!/bin/bash
# Local server trust regression (real LocalServerTrust.swift): relay, tunnels, web pages and DNS rebinding are not "this Mac".
set -euo pipefail
cd "$(dirname "$0")/../.."
for d in /Volumes/MAC/CodeTunerBuild /Volumes/MicroCodeBuild; do [ -d "$d" ] && export TMPDIR="$d/tmp" && break; done
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-localtrust.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
cp Scripts/tests/local-server-trust-regression.swift "$out_dir/main.swift"
swiftc MicroCode/Services/LocalServerTrust.swift "$out_dir/main.swift" -o "$out_dir/local-server-trust"
"$out_dir/local-server-trust"
