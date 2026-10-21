#!/usr/bin/env bash
# 2012 Mac mini: sherpa-onnx over shards FIRST..LAST, one after another, then re-score (#145). Resumable.
# Started with nohup through linux-sherpa-launch.sh, which exports the settings below.
set -uo pipefail
export PATH=/usr/bin:/bin
ROOT="$HOME/edacc-eval"
export PYTHONPATH="$ROOT/tool"
FIRST="${SHERPA_FIRST:-1}"; LAST="${SHERPA_LAST:-1}"; REPEATS="${SHERPA_REPEATS:-1}"; THREADS="${SHERPA_THREADS:-4}"
MODEL="$ROOT/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"
mkdir -p "$ROOT/results"
for k in $(seq "$FIRST" "$LAST"); do
  name=$(printf 'shard-%03d' "$k")
  echo "$(date -Is) sherpa $name start (repeats $REPEATS)"
  nice -n 10 "$ROOT/venv/bin/python" -m edacc_eval.cli sherpa --shard-dir "$ROOT/shards/$name" \
    --results "$ROOT/results/sherpa-$name.jsonl" --model-dir "$MODEL" --repeats "$REPEATS" --threads "$THREADS" \
    --status "$ROOT/sherpa-status.json"
  echo "$(date -Is) sherpa $name done"
  "$ROOT/tool/linux-score.sh"
done
echo "$(date -Is) SHERPA-ALL-DONE"
