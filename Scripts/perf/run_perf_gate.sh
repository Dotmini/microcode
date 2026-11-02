#!/bin/bash
# MicroCode performance gate: correctness fuzz + hard budgets for the hot paths fixed in v2.5.35.
# Usage: Scripts/perf/run_perf_gate.sh [streams]   (default 3000)
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mc_perf_gate.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
STREAMS="${1:-3000}"

# Pick a swiftc that can actually link the stdlib for this SDK (Xcode first, CommandLineTools fallback).
pick_swiftc() {
  if [ -n "${SWIFTC:-}" ]; then echo "$SWIFTC"; return; fi
  local probe="$WORK/probe.swift"; echo 'print(1)' > "$probe"
  if xcrun swiftc -O "$probe" -o "$WORK/probe" >/dev/null 2>&1; then echo "xcrun swiftc"; return; fi
  echo "/Library/Developer/CommandLineTools/usr/bin/swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -target arm64-apple-macosx14.0"
}
SWIFTC_CMD="$(pick_swiftc)"
echo "perf-gate: using $SWIFTC_CMD"

# 1. Sanitizer: original function is extracted verbatim from AIClient.swift so the oracle can never drift.
{
  echo "import Foundation"
  echo "enum AIStructuredTurnCodec {"
  awk '/static func stripToolCallArtifacts/{p=1} /static func stripThoughtTags/{p=0} p' MicroCode/Services/AIClient.swift
  echo "}"
} > "$WORK/Orig.swift"
cp MicroCode/Services/StreamingArtifactSanitizer.swift "$WORK/San.swift"
cp Scripts/perf/sanitizer_fuzz_main.swift "$WORK/main.swift"
$SWIFTC_CMD -O "$WORK/Orig.swift" "$WORK/San.swift" "$WORK/main.swift" -o "$WORK/sanfuzz"
"$WORK/sanfuzz" "$STREAMS"

# 1b. Loopback MCP bridge origin/host policy + device error classifier: extracted verbatim from source.
{
  echo "import Foundation"
  echo "enum MCPServer {"
  awk '/nonisolated static func isAllowedBridgeOrigin/{p=1} /private func bridgeJSON/{p=0} p' MicroCode/Services/MCPServer.swift
  echo "}"
  echo "enum DeviceRuntimeService {"
  awk '/nonisolated static func friendlyDeviceFailure/{p=1} /private func classifyDeviceFailure/{p=0} p' MicroCode/Services/DeviceRuntimeService.swift
  echo "}"
} > "$WORK/BridgePolicy.swift"
mkdir -p "$WORK/bp" && cp "$WORK/BridgePolicy.swift" "$WORK/bp/BridgePolicy.swift" && cp Scripts/perf/bridge_policy_test_main.swift "$WORK/bp/main.swift"
$SWIFTC_CMD -O "$WORK/bp/BridgePolicy.swift" "$WORK/bp/main.swift" -o "$WORK/bridgepolicy"
"$WORK/bridgepolicy"

# 1c. Android PNG-fallback incremental scan must behave exactly like the previous full-buffer scan.
mkdir -p "$WORK/png" && cp Scripts/perf/png_scan_fuzz_main.swift "$WORK/png/main.swift"
$SWIFTC_CMD -O "$WORK/png/main.swift" -o "$WORK/pngscan"
"$WORK/pngscan"

# 2. Editor lexer cache differential fuzz (added by the editor work), if present.
if [ -x Scripts/perf/run_lexer_fuzz.sh ]; then
  SWIFTC_CMD="$SWIFTC_CMD" Scripts/perf/run_lexer_fuzz.sh
fi
echo "perf-gate: PASS"
