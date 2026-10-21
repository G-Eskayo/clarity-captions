#!/bin/bash
# M4 Mac mini: one-shard extras for #145, run in sequence after the main cycle for that shard:
#   1. sherpa-onnx on the M4 (repeat 1) and an identical-text check against the 2012 mini's results,
#   2. extra engines on the shard (e.g. the whisperkit-nogate diagnostic), repeat 1,
#   3. the live-latency sample (engine-eval latency), clips up to 30 s.
# Then push, re-score on the 2012 mini, copy the report back, delete the shard audio. Start with
# EVAL_DRIVER=m4-shard-extras.sh m4-launch.sh SHARD 1 1 (nohup + Terminal window). Every step is resumable.
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
REMOTE="${EVAL_REMOTE:-mac-mini-2012}"
WORK="${EVAL_WORK:-$HOME/edacc-eval}"
REPO="${EVAL_REPO:?}"
K="${EVAL_FIRST:-1}"
name=$(printf 'shard-%03d' "$K")
EXTRA_ENGINES="${EVAL_EXTRA_ENGINES:-whisperkit-nogate}"
BIN="$REPO/Packages/EngineEval/.build/release/engine-eval"
STATUS="$WORK/status.txt"
export PYTHONPATH="$REPO/scripts/engine-eval"
mkdir -p "$WORK/shards" "$WORK/results/latency" "$WORK/check" "$WORK/logs"
status() { printf 'Engine accuracy test (#145): %s extras\nStage: %s\nUpdated: %s\n' "$name" "$1" "$(date '+%F %T')" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"; }

status "fetching $name"
rsync -a --checksum "$REMOTE:edacc-eval/shards/$name/" "$WORK/shards/$name/" || { echo "fetch failed"; exit 1; }
(cd "$REPO/Packages/EngineEval" && swift build -c release 2>&1 | tail -1)

if [ "${EVAL_SHERPA_CHECK:-1}" = "1" ]; then
  status "sherpa-onnx on the M4 (cross-machine check)"
  "$WORK/venv/bin/python" -m edacc_eval.cli sherpa --shard-dir "$WORK/shards/$name" \
    --results "$WORK/check/sherpa-m4-$name.jsonl" --model-dir "$WORK/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8" \
    --repeats 1 --threads "${EVAL_SHERPA_THREADS:-8}" --status "$WORK/status-engine.json"
  rsync -a "$REMOTE:edacc-eval/results/sherpa-$name.jsonl" "$WORK/check/sherpa-2012-$name.jsonl"
  "$WORK/venv/bin/python" -m edacc_eval.cli compare "$WORK/check/sherpa-m4-$name.jsonl" \
    "$WORK/check/sherpa-2012-$name.jsonl" --engine sherpa-onnx | tee "$WORK/check/sherpa-compare-$name.json"
fi

if [ -n "$EXTRA_ENGINES" ]; then
  status "extra engines on $name: $EXTRA_ENGINES"
  "$BIN" run --shard-dir "$WORK/shards/$name" --results "$WORK/results/apple-$name.jsonl" --engines "$EXTRA_ENGINES" \
    --repeats 1 --models-dir "$WORK/models" --status "$WORK/status-engine.json"
fi

if [ "${EVAL_LATENCY:-1}" = "1" ]; then
  status "live-latency sample on $name (Apple runs in real time)"
  "$BIN" latency --shard-dir "$WORK/shards/$name" --out "$WORK/results/latency/latency-$name.jsonl" \
    --models-dir "$WORK/models" --status "$WORK/status-engine.json"
fi

status "pushing results and re-scoring"
rsync -a "$WORK/results/apple-$name.jsonl" "$REMOTE:edacc-eval/results/"
ssh "$REMOTE" 'mkdir -p edacc-eval/results/latency'
[ -f "$WORK/results/latency/latency-$name.jsonl" ] && rsync -a "$WORK/results/latency/latency-$name.jsonl" "$REMOTE:edacc-eval/results/latency/"
ssh "$REMOTE" 'edacc-eval/tool/linux-score.sh'
rsync -a "$REMOTE:edacc-eval/report/engine-accuracy-comparison.md" "$WORK/report/" \
  && cp "$WORK/report/engine-accuracy-comparison.md" "$REPO/docs/perf/engine-accuracy-comparison.md"
rm -rf "$WORK/shards/$name"
status "FINISHED"
echo "$(date '+%F %T') EXTRAS-DONE"
