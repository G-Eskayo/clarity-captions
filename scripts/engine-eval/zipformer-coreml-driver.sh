#!/bin/bash
# The Hebrew zipformer on Core ML (#220), one command, on an Apple-silicon Mac:
#   EVAL_REPO=<clarity-captions checkout> ZC_PY=<python with coremltools, onnx, torchaudio> \
#     scripts/engine-eval/zipformer-coreml-driver.sh
# Fetches ivrit.ai's ONNX export of the zipformer (pinned), converts it to Core ML (fp32, fp16, int8 and 6-, 4-, 3-
# and 2-bit palettized encoders), scores every build on eval-d1 and eval-whatsapp, measures latency and memory, and
# writes the report. Needs the eval-d1 and eval-whatsapp shards that hebrew-driver.sh cuts ($ZC_WORK/shards), and,
# for the reference rows, #217's sherpa-onnx int8 and Apple result files in $ZC_WORK/results. Local only: no cloud
# service, no paid API. Resumable: scoring skips clips already in a result file. Method: docs/perf/hebrew-coreml-design.md.
# ZC_DELETE=1 deletes the ONNX download, the builds and the audio at the end (the report and result lines stay).
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
REPO="${EVAL_REPO:?EVAL_REPO must point at the clarity-captions checkout}"
WORK="${ZC_WORK:-$HOME/hebrew-eval-220}"
PY="${ZC_PY:?ZC_PY must be a python with coremltools 9, onnx and torchaudio}"
VARIANTS="${ZC_VARIANTS:-fp32 fp16 int8 pal6 pal4 pal3 pal2}"
LATENCY_CLIPS="${ZC_LATENCY_CLIPS:-5}"
UNITS="${ZC_COMPUTE_UNITS:-CPU_AND_GPU}"  # the ANE compiler rejects this encoder (see the design doc)
export PYTHONPATH="$REPO/scripts/engine-eval"
mkdir -p "$WORK/onnx" "$WORK/builds" "$WORK/results" "$WORK/latency" "$WORK/report"

for f in onnx/encoder.onnx onnx/decoder.onnx onnx/joiner.onnx onnx/config.json onnx/tokens.txt; do  # pinned, CC BY 4.0
  out="$WORK/onnx/$(basename "$f")"
  [ -s "$out" ] || curl -sfL --retry 3 -o "$out.part" \
    "https://huggingface.co/ivrit-ai/zipformer2-66m-streaming-he/resolve/ee769a2/$f" && mv "$out.part" "$out" 2>/dev/null
  [ -s "$out" ] || { echo "fetch failed: $f"; exit 1; }
done

todo=""
for v in $VARIANTS; do [ -f "$WORK/builds/$v/sizes.json" ] || todo="$todo $v"; done
[ -z "$todo" ] || "$PY" -m zipformer_coreml.convert --onnx-dir "$WORK/onnx" --out "$WORK/builds" --variants $todo \
  || { echo "conversion failed"; exit 1; }

failed=0
for v in $VARIANTS; do
  for set in eval-d1 eval-whatsapp; do
    echo "$(date '+%F %T') score $v $set"
    nice -n 15 "$PY" -m zipformer_coreml.run score --variant "$v" --builds "$WORK/builds" \
      --shard-dir "$WORK/shards/$set/shard-001" --results "$WORK/results/$set-shard-001-coreml-$v.jsonl" --compute-units "$UNITS" || failed=1
  done
  echo "$(date '+%F %T') latency $v"
  clips=$(ls "$WORK/shards/eval-d1/shard-001/audio/"*.wav | head -n "$LATENCY_CLIPS")
  "$PY" -m zipformer_coreml.run latency --variant "$v" --builds "$WORK/builds" --clips $clips \
    --out "$WORK/latency/$v.json" --compute-units "$UNITS" > /dev/null || failed=1
done
"$PY" -m zipformer_coreml.report --shards "$WORK/shards" --results "$WORK/results" --builds "$WORK/builds" \
  --latency "$WORK/latency" --out "$WORK/report/hebrew-coreml-comparison.md" --json-out "$WORK/report/hebrew-coreml.json" \
  || failed=1
if [ "${ZC_DELETE:-0}" = 1 ] && [ $failed = 0 ]; then
  rm -rf "${WORK:?}/onnx" "${WORK:?}/builds" "${WORK:?}/shards"/*/shard-*/audio
fi
echo "$(date '+%F %T') ZIPFORMER-COREML-DONE (errors: $failed)"
exit $failed
