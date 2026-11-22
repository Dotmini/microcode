#!/bin/bash
# curl secret-argument regression (real CurlSecretArguments.swift): tokens and bodies never on the command line.
set -euo pipefail
cd "$(dirname "$0")/../.."
for d in /Volumes/MAC/CodeTunerBuild /Volumes/MicroCodeBuild; do [ -d "$d" ] && export TMPDIR="$d/tmp" && break; done
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-curlargs.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
cp Scripts/tests/curl-secret-arguments-regression.swift "$out_dir/main.swift"
swiftc MicroCode/Services/CurlSecretArguments.swift "$out_dir/main.swift" -o "$out_dir/curl-secret-arguments"
"$out_dir/curl-secret-arguments"
