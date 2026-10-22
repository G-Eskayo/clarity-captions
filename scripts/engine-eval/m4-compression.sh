#!/bin/bash
# M4 Mac mini: the Parakeet Ultra size test (#150), one sequential chain, resumable at every step.
#   1. export the Ultra fp16 encoder with FluidInference/mobius and palettize it (compress_parakeet.py)
#   2. every shard, one run per clip, for the compressed and published small builds (m4-driver.sh)
#   3. the live-latency sample on shard 1 for the same builds
#   4. process memory footprint for each build and for the baselines
#   5. sizes of the published folders, push everything, re-score on the 2012 mini
# Start with: EVAL_DRIVER=m4-compression.sh m4-launch.sh 1 32 1 (nohup, nice +15, Terminal window).
set -uo pipefail
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
REMOTE="${EVAL_REMOTE:-mac-mini-2012}"
WORK="${EVAL_WORK:-$HOME/edacc-eval}"
REPO="${EVAL_REPO:?}"
HERE="$REPO/scripts/engine-eval"
C="${EVAL_CONVERT:-$WORK/convert}"
M="$C/mobius/models/stt"
CPY="$M/parakeet-tdt-v3-0.6b/coreml/.venv/bin/python"
ENGINES="${EVAL_COMP_ENGINES:-local:ultra-pal6,local:ultra-pal4,parakeet-v3-int4,parakeet-redux}"
MEM_ENGINES="${EVAL_MEM_ENGINES:-parakeet-ultra,parakeet-v2,apple,$ENGINES}"
BIN="$REPO/Packages/EngineEval/.build/release/engine-eval"
SIZES="$WORK/results/sizes.json"
export PYTHONPATH="$HERE"
STATUS="$WORK/status.txt"
status() { printf 'Parakeet size test (#150)\nStage: %s\nUpdated: %s\n' "$1" "$(date '+%F %T')" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"; }
mkdir -p "$WORK/results/latency" "$WORK/results/memory" "$WORK/models/variants"

# Step 1 can also run elsewhere (the M4's disk is tight): copy the built folders into $WORK/models/variants and the
# sizes into $SIZES, then start with EVAL_SKIP_BUILD=1.
if [ "${EVAL_SKIP_BUILD:-0}" != "1" ]; then
status "1/5 exporting the Ultra fp16 encoder (mobius)"
if [ ! -d "$C/work/encoder_fp16_ultra.mlpackage" ]; then
  (cd "$M/parakeet-redux/coreml" && "$CPY" export_encoder_fp16.py --hf-dir "$C/work/hf" --work "$C/work" --name ultra) \
    || { echo "fp16 export failed"; exit 1; }
fi
status "1/5 palettizing the encoder (6-bit, 4-bit)"
"$CPY" "$HERE/compress_parakeet.py" "$C/work/encoder_fp16_ultra.mlpackage" --base "$WORK/models/fluidaudio/parakeet-ultra" \
  --out "$WORK/models/variants" --sizes "$SIZES" --workers "${EVAL_KMEANS_WORKERS:-6}" || { echo "palettization failed"; exit 1; }
fi
(cd "$REPO/Packages/EngineEval" && swift build -c release 2>&1 | tail -1)

status "2/5 accuracy on every shard: $ENGINES"
EVAL_ENGINES="$ENGINES" EVAL_FIRST=1 EVAL_MAX_SHARDS=32 EVAL_REPEATS=1 EVAL_SHERPA=0 EVAL_NO_FINISH=1 "$HERE/m4-driver.sh"

status "3/5 live-latency sample (shard 1)"
rsync -a --checksum "$REMOTE:edacc-eval/shards/shard-001/" "$WORK/shards/shard-001/"
"$BIN" latency --shard-dir "$WORK/shards/shard-001" --out "$WORK/results/latency/latency-shard-001.jsonl" \
  --engines "$ENGINES" --models-dir "$WORK/models" --status "$WORK/status-engine.json"

status "4/5 memory footprint per build"
IFS=',' read -ra MEMS <<< "$MEM_ENGINES"
for e in "${MEMS[@]}"; do
  "$BIN" memory --shard-dir "$WORK/shards/shard-001" --engines "$e" --clips 60 --models-dir "$WORK/models" \
    --out "$WORK/results/memory/memory.jsonl" || echo "memory $e failed"
done
rm -rf "$WORK/shards/shard-001"

status "5/5 sizes, push, re-score"
F="$WORK/models/fluidaudio"
V3="Preprocessor.mlmodelc,Decoder.mlmodelc,JointDecisionv3.mlmodelc,parakeet_vocab.json"
python3 -m edacc_eval.cli sizes --out "$SIZES" --model parakeet-ultra-coreml --folder "$F/parakeet-ultra" \
  --include "Encoder.mlmodelc,$V3" --method "as published: encoder int8 linear per channel (FluidAudio)"
python3 -m edacc_eval.cli sizes --out "$SIZES" --model parakeet-tdt-0.6b-v2-coreml --folder "$F/parakeet-tdt-0.6b-v2" \
  --include "Preprocessor.mlmodelc,Encoder.mlmodelc,Decoder.mlmodelc,JointDecision.mlmodelc,parakeet_vocab.json"
for d in "$F"/*; do
  case "$(basename "$d")" in
    *v3*) [ -d "$d/EncoderInt4.mlmodelc" ] && python3 -m edacc_eval.cli sizes --out "$SIZES" \
            --model parakeet-tdt-0.6b-v3-coreml-int4 --folder "$d" --include "EncoderInt4.mlmodelc,$V3" \
            --method "as published: v3 encoder 4-bit (FluidAudio .int4)" ;;
    *redux*) python3 -m edacc_eval.cli sizes --out "$SIZES" --model parakeet-redux-coreml --folder "$d" \
            --include "Encoder.mlmodelc,$V3" --method "as published: Redux, 2-bit ternary re-training of v3" ;;
  esac
done
rsync -a "$WORK/results/latency/latency-shard-001.jsonl" "$REMOTE:edacc-eval/results/latency/"
ssh "$REMOTE" 'mkdir -p edacc-eval/results/memory'
rsync -a "$WORK/results/memory/memory.jsonl" "$REMOTE:edacc-eval/results/memory/"
rsync -a "$SIZES" "$REMOTE:edacc-eval/results/sizes.json"
ssh "$REMOTE" 'edacc-eval/tool/linux-score.sh'
rsync -a "$REMOTE:edacc-eval/report/engine-accuracy-comparison.md" "$WORK/report/"
status "FINISHED"
echo "$(date '+%F %T') COMPRESSION-DONE"
