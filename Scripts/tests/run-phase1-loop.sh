#!/bin/bash
# Phase 1 agent-loop regression: compiles the real streaming primitives with the regression driver.
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ -d "/Volumes/MAC/CodeTunerBuild" ]; then
  export TMPDIR="/Volumes/MAC/CodeTunerBuild/tmp"
elif [ -d "/Volumes/MicroCodeBuild" ]; then
  export TMPDIR="/Volumes/MicroCodeBuild/tmp"
fi
mkdir -p "${TMPDIR:-/tmp}"

out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-phase1.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT

swiftc -parse-as-library \
  MicroCode/Services/AIStreamPrimitives.swift \
  Scripts/tests/phase1-loop-regression.swift \
  -o "$out_dir/phase1"
"$out_dir/phase1"
