#!/bin/bash
# Editor typing regression: debounced binding echoes must never revert unsynced keystrokes.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [ -d "/Volumes/MAC/CodeTunerBuild" ]; then export TMPDIR="/Volumes/MAC/CodeTunerBuild/tmp"; fi
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-editor-sync.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
swiftc -parse-as-library \
  MicroCode/SyntaxEngine/EditorBindingSyncPolicy.swift \
  Scripts/tests/editor-binding-sync-regression.swift \
  -o "$out_dir/editor-sync"
"$out_dir/editor-sync"
