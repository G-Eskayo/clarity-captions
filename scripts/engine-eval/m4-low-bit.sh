#!/bin/bash
# M4 Mac mini: the low-bit Parakeet Ultra test (#203), one sequential chain, resumable at every step.
#   1. mobius env + fp16 Ultra encoder export, then 3-bit, 2-bit and mixed 2/4/6 builds (compress_parakeet.py);
#      the export scratch (about 10 GB) is deleted once the builds exist
#   2. EdAcc shards rebuilt here, one parquet at a time (the 2012 mini that keeps them may be offline), checked
#      clip for clip against #150's result files so the new rows score exactly the clips the old ones did
#   3. every shard, one run per clip, for the new builds and 6-bit again (same machine, same hour, so the speed
#      comparison is fair), scored locally; machine load sampled every 30 s the whole time
#   4. the live-latency sample (shard 1) and memory footprint for the same builds
#   5. sizes, report, delete the shards
# Start: EVAL_REPO=<worktree> nohup nice -n 15 scripts/engine-eval/m4-low-bit.sh >> ~/edacc-eval/logs/203.log 2>&1 &
# EVAL_SKIP_BUILD=1 skips step 1 (builds made elsewhere and copied into models/variants).
set -uo pipefail
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
WORK="${EVAL_WORK:-$HOME/edacc-eval}"
REPO="${EVAL_REPO:?}"
HERE="$REPO/scripts/engine-eval"
C="${EVAL_CONVERT:-$WORK/convert}"
M="$C/mobius/models/stt"
CPY="$M/parakeet-tdt-v3-0.6b/coreml/.venv/bin/python"
PY="$WORK/venv/bin/python"
BUILDS="${EVAL_LOWBIT_BUILDS:-ultra-pal3,ultra-pal2,ultra-mixed246}"
ENGINES="${EVAL_LOWBIT_ENGINES:-local:ultra-pal6,local:ultra-pal3,local:ultra-pal2,local:ultra-mixed246}"
R="$WORK/results-203"            # its own result files: the #150 files already hold 6-bit lines that resume would skip
S="$WORK/shards-203"
BIN="$REPO/Packages/EngineEval/.build/release/engine-eval"
SIZES="$R/sizes.json"
LOAD="$R/load.tsv"
export PYTHONPATH="$HERE"
STATUS="$WORK/status.txt"
status() { printf 'Low-bit Ultra test (#203)\nStage: %s\nUpdated: %s\n' "$1" "$(date '+%F %T')" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"; }
mkdir -p "$R/latency" "$R/memory" "$WORK/models/variants" "$WORK/logs"

# Load sampler: 1-minute load average, CPU idle and the busiest processes, every 30 s, until this script exits.
[ -s "$LOAD" ] || printf 'time\tload1\tload5\tcpu_idle_pct\ttop_processes\n' > "$LOAD"
( while kill -0 $$ 2>/dev/null; do
    la=$(sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1"\t"$2}')
    idle=$(top -l 1 -n 0 | awk '/CPU usage/ {gsub("%","",$7); print $7}')
    procs=$(ps -Ao pcpu=,comm= -r | head -3 | awk '{n=split($2,p,"/"); printf "%s %s%%; ", p[n], $1}')
    printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$la" "$idle" "$procs" >> "$LOAD"
    sleep 30
  done ) &

if [ "${EVAL_SKIP_BUILD:-0}" != "1" ]; then
  status "1/5 mobius env and fp16 Ultra encoder export"
  if [ ! -x "$CPY" ]; then
    [ -d "$C/mobius" ] || (mkdir -p "$C" && cd "$C" && git clone -q --depth 1 --filter=blob:none --sparse \
      https://github.com/FluidInference/mobius.git && cd mobius && git sparse-checkout set \
      models/stt/parakeet-redux/coreml models/stt/parakeet-tdt-v3-0.6b/coreml) || { echo "mobius clone failed"; exit 1; }
    (cd "$M/parakeet-tdt-v3-0.6b/coreml" && UV_CACHE_DIR="$C/cache/uv" uv sync) || { echo "uv sync failed"; exit 1; }
  fi
  mkdir -p "$C/work/hf"
  for f in config.json model.safetensors tokenizer.json README.md; do
    [ -s "$C/work/hf/$f" ] || curl -sfL -C - -o "$C/work/hf/$f" "https://huggingface.co/moondream/parakeet-ultra/resolve/main/$f" \
      || { echo "download $f failed"; exit 1; }
  done
  if [ ! -d "$C/work/encoder_fp16_ultra.mlpackage" ]; then
    (cd "$M/parakeet-redux/coreml" && HF_HOME="$C/cache/hf" "$CPY" export_encoder_fp16.py --hf-dir "$C/work/hf" \
      --work "$C/work" --name ultra) || { echo "fp16 export failed"; exit 1; }
  fi
  status "1/5 palettizing the encoder ($BUILDS)"
  # One k-means worker: a pool crashed with "Pool not running" in #150.
  "$CPY" "$HERE/compress_parakeet.py" "$C/work/encoder_fp16_ultra.mlpackage" --base "$WORK/models/fluidaudio/parakeet-ultra" \
    --out "$WORK/models/variants" --variants "$BUILDS" --sizes "$SIZES" --workers 1 || { echo "palettization failed"; exit 1; }
  rm -rf "$C"
fi
(cd "$REPO/Packages/EngineEval" && swift build -c release 2>&1 | tail -1)

status "2/5 EdAcc shards, one parquet at a time"
if [ ! -s "$S/index.json" ]; then
  curl -sf "https://huggingface.co/api/datasets/edinburghcstr/edacc/tree/main/data" | "$PY" -c \
    'import json,sys; [print("https://huggingface.co/datasets/edinburghcstr/edacc/resolve/main/"+f["path"]) for f in json.load(sys.stdin) if f["path"].endswith(".parquet")]' \
    > "$R/edacc-urls.txt" || { echo "cannot list EdAcc"; exit 1; }
  "$PY" -m edacc_eval.cli build-shards-staged --urls "$R/edacc-urls.txt" --download-dir "$WORK/edacc-download" \
    --out "$S" || { echo "shard build failed"; exit 1; }
fi
"$PY" -m edacc_eval.cli match-shards --shards "$S" --results "$WORK/results" > "$R/shard-match.json" \
  || { echo "rebuilt shards differ from #150's; see $R/shard-match.json"; exit 1; }

N=$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["n_shards"])' "$S/index.json")
for k in $(seq 1 "$N"); do
  name=$(printf 'shard-%03d' "$k")
  marker="$R/done-$name"
  [ -e "$marker" ] && continue
  status "3/5 accuracy, $name of $N: $ENGINES"
  "$BIN" run --shard-dir "$S/$name" --results "$R/apple-$name.jsonl" --engines "$ENGINES" --repeats 1 \
    --models-dir "$WORK/models" --status "$WORK/status-engine.json" && touch "$marker"
  "$PY" -m edacc_eval.cli report --shards "$S" --results "$R" --out "$R/report.md" --json-out "$R/report.json" \
    > /dev/null || echo "score failed after $name"
done

status "4/5 live latency (shard 1) and memory"
"$BIN" latency --shard-dir "$S/shard-001" --out "$R/latency/latency-shard-001.jsonl" \
  --engines "$ENGINES" --models-dir "$WORK/models" --status "$WORK/status-engine.json"
IFS=',' read -ra MEMS <<< "$ENGINES"
for e in "${MEMS[@]}"; do
  "$BIN" memory --shard-dir "$S/shard-001" --engines "$e" --clips 60 --models-dir "$WORK/models" \
    --out "$R/memory/memory.jsonl" || echo "memory $e failed"
done

status "5/5 sizes and report"
for e in "${MEMS[@]}"; do
  b="${e#local:}"   # 6-bit too, so its row sits next to the new ones
  m=$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["method"])' "$WORK/models/variants/$b/variant.json")
  "$PY" -m edacc_eval.cli sizes --out "$SIZES" --model "$b" --folder "$WORK/models/variants/$b" --method "$m" \
    --license "CC BY 4.0 (attribution in NOTICE.txt)"
done
"$PY" -m edacc_eval.cli report --shards "$S" --results "$R" --out "$R/report.md" --json-out "$R/report.json"
rm -rf "$S" "$WORK/edacc-download"
status "FINISHED"
echo "$(date '+%F %T') LOWBIT-DONE"
