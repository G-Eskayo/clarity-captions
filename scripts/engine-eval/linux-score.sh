#!/usr/bin/env bash
# 2012 Mac mini: re-score every result so far and rewrite the report (#145). Serialized with flock because the
# M4 driver and the sherpa-onnx loop both call it after each cycle.
set -euo pipefail
export PATH=/usr/bin:/bin
ROOT="$HOME/edacc-eval"
export PYTHONPATH="$ROOT/tool"
mkdir -p "$ROOT/report"
exec 9>"$ROOT/report/.lock"
flock 9
"$ROOT/venv/bin/python" -m edacc_eval.cli report --shards "$ROOT/shards" --results "$ROOT/results" \
  --out "$ROOT/report/engine-accuracy-comparison.md" --json-out "$ROOT/report/engine-accuracy-comparison.json"
echo "scored $(date -Is)"
