#!/bin/bash
# Claim-vs-evidence check + P1 harness policy (real AgentClaimCheck.swift).
set -euo pipefail
cd "$(dirname "$0")/../.."
for d in /Volumes/MAC/CodeTunerBuild /Volumes/MicroCodeBuild; do [ -d "$d" ] && export TMPDIR="$d/tmp" && break; done
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-claimcheck.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
cp Scripts/tests/agent-claim-check-regression.swift "$out_dir/main.swift"
swiftc MicroCode/Services/AgentCore/AgentClaimCheck.swift "$out_dir/main.swift" -o "$out_dir/claim-check"
"$out_dir/claim-check"
