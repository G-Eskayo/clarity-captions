#!/bin/bash
# M4 Mac mini: the language accuracy run (#158). A sequential loop: for each language, for each shard, Apple with
# each of its locales, Parakeet Ultra (FluidAudio), then sherpa-onnx (Parakeet v3 and Ultra); then re-score and
# rewrite the report. Everything is local: the FLEURS shards are small (see language-accuracy-design.md).
# Resumable: every engine skips (clip, engine, model, repeat) already in the shard's result file.
# Start it with m4-launch.sh (EVAL_DRIVER=m4-language-driver.sh), not directly.
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

REPO="${EVAL_REPO:?EVAL_REPO must point at the clarity-captions worktree}"
WORK="${EVAL_WORK:-$HOME/edacc-eval}"          # models, venv and the status window (shared with #145)
DATA="${LANG_DATA:-$HOME/fleurs-eval}"         # shards, results, report for this run
LANGS="${LANG_LANGS:-es fr de}"
THREADS="${EVAL_SHERPA_THREADS:-8}"
SHERPA_MODELS="${LANG_SHERPA_MODELS:-sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8 sherpa-onnx-nemo-parakeet-ultra-int8}"
BIN="$REPO/Packages/EngineEval/.build/release/engine-eval"
PY="$WORK/venv/bin/python"
STATUS="$WORK/status.txt"
export PYTHONPATH="$REPO/scripts/engine-eval"
mkdir -p "$DATA/results" "$DATA/report" "$WORK/logs"

status() {  # stage line for the visible window; engine progress lives in status-engine.json
  printf 'Language accuracy test (#158)\nLanguage %s, %s\nStage: %s\nUpdated: %s\n' \
    "$1" "$2" "$3" "$(date '+%Y-%m-%d %H:%M:%S')" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
}
field() { "$PY" -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print(" ".join(v) if isinstance(v, list) else v)' "$@"; }
rescore() {
  "$PY" -m edacc_eval.cli report-languages --shards "$DATA/shards" --results "$DATA/results" \
    --out "$DATA/report/language-accuracy-comparison.md" --json-out "$DATA/report/language-accuracy.json" \
    || echo "re-score failed"
}

echo "$(date '+%F %T') language driver start: $LANGS"
(cd "$REPO/Packages/EngineEval" && swift build -c release) || { echo "build failed"; exit 1; }

failed=0
for lang in $LANGS; do
  index="$DATA/shards/$lang/index.json"
  [ -f "$index" ] || { echo "no shards for $lang ($index)"; failed=1; continue; }
  locales=$(field "$index" locales)
  for shard in $(field "$index" shards); do
    dir="$DATA/shards/$lang/$shard"
    for loc in $locales; do
      status "$lang" "$shard" "Apple SpeechAnalyzer $loc"
      "$BIN" run --shard-dir "$dir" --results "$DATA/results/$lang-$shard-swift.jsonl" --engines apple \
        --locale "$loc" --models-dir "$WORK/models" --status "$WORK/status-engine.json" || failed=1
    done
    status "$lang" "$shard" "Parakeet Ultra (FluidAudio)"
    "$BIN" run --shard-dir "$dir" --results "$DATA/results/$lang-$shard-swift.jsonl" --engines parakeet-ultra \
      --models-dir "$WORK/models" --status "$WORK/status-engine.json" || failed=1
    for m in $SHERPA_MODELS; do
      status "$lang" "$shard" "sherpa-onnx $m"
      "$PY" -m edacc_eval.cli sherpa --shard-dir "$dir" --results "$DATA/results/$lang-$shard-sherpa.jsonl" \
        --model-dir "$WORK/models/$m" --threads "$THREADS" --status "$WORK/status-engine.json" || failed=1
    done
    rescore
    echo "$(date '+%F %T') $lang $shard done"
  done
done
rescore
status "all" "-" "FINISHED (errors: $failed)"
echo "$(date '+%F %T') DRIVER-DONE (errors: $failed)"
