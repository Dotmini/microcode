#!/bin/bash
# Differential fuzz of the editor's incremental syntax cache (SyntaxCache.swift) against a from-scratch tokenisation.
# Called by run_perf_gate.sh (SWIFTC_CMD is exported there); can also be run directly.
set -euo pipefail
cd "$(dirname "$0")/../.."
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mc_lexer_fuzz.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
SWIFTC_CMD="${SWIFTC_CMD:-xcrun swiftc}"
SE=MicroCode/SyntaxEngine
# Top-level code is only allowed in a file literally named main.swift.
cp Scripts/perf/lexer_fuzz_main.swift "$WORK/main.swift"
$SWIFTC_CMD -O -DNEWAPI -o "$WORK/lexfuzz" \
  "$WORK/main.swift" Scripts/perf/lexer_fuzz_stub.swift \
  "$SE/Lexer.swift" "$SE/Token.swift" "$SE/SyntaxCache.swift"
# 3 languages x EDITS edits; several batch sizes exercise pending dirty regions.
EDITS="${LEXFUZZ_EDITS:-1200}"
"$WORK/lexfuzz" --edits "$EDITS" --seed 20260211 --batch 3
"$WORK/lexfuzz" --edits "$EDITS" --seed 7 --batch 1
"$WORK/lexfuzz" --edits "$EDITS" --seed 3 --batch 6
echo "lexer-fuzz: PASS"
