#!/usr/bin/env bash
# 2012 Mac mini: sherpa-onnx, one shard after another, taking the next unclaimed shard from the shared queue
# (linux-claim.sh) so the M4 can work the same queue without duplicates; re-scores after each shard (#145).
# Started with nohup through linux-sherpa-launch.sh, which exports the settings below. Resumable.
set -uo pipefail
export PATH=/usr/bin:/bin
ROOT="$HOME/edacc-eval"
export PYTHONPATH="$ROOT/tool"
FIRST="${SHERPA_FIRST:-1}"; LAST="${SHERPA_LAST:-1}"; REPEATS="${SHERPA_REPEATS:-1}"; THREADS="${SHERPA_THREADS:-4}"
HOST="$(hostname)"
MODEL="$ROOT/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"
mkdir -p "$ROOT/results"
while true; do
  k=$("$ROOT/tool/linux-claim.sh" claim "$HOST" "$FIRST" "$LAST")
  [ -z "$k" ] && break
  name=$(printf 'shard-%03d' "$k")
  echo "$(date -Is) sherpa $name start (repeats $REPEATS)"
  if "$ROOT/venv/bin/python" -m edacc_eval.cli sherpa --shard-dir "$ROOT/shards/$name" \
      --results "$ROOT/results/sherpa-$name.jsonl" --model-dir "$MODEL" --repeats "$REPEATS" --threads "$THREADS" \
      --status "$ROOT/sherpa-status.json"; then
    "$ROOT/tool/linux-claim.sh" done "$k"
    echo "$(date -Is) sherpa $name done"
  else
    echo "$(date -Is) sherpa $name failed; stopping (rerun resumes)"; break
  fi
  "$ROOT/tool/linux-score.sh"
done
echo "$(date -Is) SHERPA-ALL-DONE"
