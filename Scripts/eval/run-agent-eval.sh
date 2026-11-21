#!/bin/bash
# Replay eval of the real MicroCode agent loop (AgentEvalRunner + AgentEvalGrader).
#   Scripts/eval/run-agent-eval.sh [path/to/MicroCode.app] [case-id]
# Env overrides: MICROCODE_AGENT_EVAL_PROVIDER, MICROCODE_AGENT_EVAL_MODEL, MICROCODE_AGENT_EVAL_TIMEOUT (s/case).
# Uses the provider/model configured in MicroCode (real API calls). Results: Scripts/eval/results/<timestamp>.jsonl
set -euo pipefail
cd "$(dirname "$0")/../.."
app="${1:-/Applications/MicroCode.app}"
bin="$app/Contents/MacOS/MicroCode"
[ -x "$bin" ] || { echo "no MicroCode binary at $bin"; exit 2; }
# The eval instance shares the chat list and settings with the app: never run both at once.
if pgrep -f "MicroCode.app/Contents/MacOS/MicroCode" >/dev/null; then
  echo "MicroCode is running. Quit it first (the eval would race it on the saved chat list)."; exit 3
fi
mkdir -p Scripts/eval/results
out="Scripts/eval/results/$(date +%Y%m%d-%H%M%S).jsonl"
export MICROCODE_AGENT_EVAL_CASES="$PWD/Scripts/eval/cases"
export MICROCODE_AGENT_EVAL_OUT="$PWD/$out"
[ -n "${2:-}" ] && export MICROCODE_AGENT_EVAL_ONLY="$2"
"$bin" 2>&1 | grep --line-buffered "\[agent-eval\]\|^    [✓✗]" || true
echo "results: $out"
python3 - "$out" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
if not rows:
    print("no results"); sys.exit(1)
print(f"{sum(r['passed'] for r in rows)}/{len(rows)} cases passed on {rows[0]['provider']}/{rows[0]['model']}")
for r in rows:
    t = r.get("trace") or {}
    print(f"  {'PASS' if r['passed'] else 'FAIL'} {r['id']:38s} {r['seconds']:4d}s  interventions={sum((t.get('interventions') or {}).values())} end={t.get('endReason')}")
sys.exit(0 if all(r['passed'] for r in rows) else 1)
PY
