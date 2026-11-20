#!/bin/bash
# Agent "working" indicator regression: it must animate without per-frame SwiftUI layout of the chat transcript.
# Opens a small window for ~6 s, so it needs a logged-in GUI session.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [ -d "/Volumes/MAC/CodeTunerBuild" ]; then export TMPDIR="/Volumes/MAC/CodeTunerBuild/tmp"; fi
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-streaming-indicator.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
swiftc -parse-as-library \
  MicroCode/Views/AI/AIStreamingThreeDotsView.swift \
  Scripts/tests/streaming-indicator-idle-regression.swift \
  -o "$out_dir/streaming-indicator-idle"
"$out_dir/streaming-indicator-idle"
