#!/bin/bash
# The Hebrew engine test (#201), one command, on an Apple-silicon Mac (macOS 26):
#   EVAL_REPO=<clarity-captions checkout> scripts/engine-eval/hebrew-driver.sh
# Fetches the pinned FLEURS he test split and the pinned models (only if missing), cuts shards, then for each shard
# runs Apple DictationTranscriber he-IL, the ivrit.ai zipformer, Nemotron 3.5 zero-shot, Parakeet-He and ivrit.ai
# Whisper turbo, and rewrites the report. Every engine runs locally; no cloud service, no paid API.
# Resumable: each engine skips clips already in the shard's result file. Method: docs/perf/hebrew-accuracy-design.md.
# Needs the Hebrew venv (sherpa-onnx 2.0.1, transformers, torch, librosa, scipy, soundfile), see the design doc.
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin

REPO="${EVAL_REPO:?EVAL_REPO must point at the clarity-captions checkout}"
WORK="${HE_WORK:-$HOME/hebrew-eval}"            # corpus, shards, models, results, venv: outside the repo
PY="${HE_PY:-$WORK/venv/bin/python}"
ENGINES="${HE_ENGINES:-apple-dictation zipformer nemotron parakeet-he whisper-ivrit}"
THREADS="${HE_THREADS:-8}"
BIN="$REPO/Packages/EngineEval/.build/release/engine-eval"
export PYTHONPATH="$REPO/scripts/engine-eval"
mkdir -p "$WORK/corpus/he_il" "$WORK/models" "$WORK/results" "$WORK/report" "$WORK/logs"

fetch() {  # fetch <repo> <revision> <dir> <file>...: pinned revisions; each model in its own folder
  local repo=$1 rev=$2 dir=$3; shift 3
  mkdir -p "$dir"
  for f in "$@"; do
    local out="$dir/$(basename "$f")"
    [ -s "$out" ] && continue
    curl -sfL --retry 3 -o "$out.part" "https://huggingface.co/$repo/resolve/$rev/$f" && mv "$out.part" "$out" \
      || { echo "fetch failed: $repo $f"; return 1; }
  done
  echo "$repo@$rev" > "$dir/SOURCE"
}

# Data: FLEURS he test split, CC BY 4.0, the commit #158 pinned. Not needed again once the shards exist.
[ -f "$WORK/shards/he/index.json" ] || fetch datasets/google/fleurs 70bb2e8 "$WORK/corpus/he_il" data/he_il/test.tsv \
  data/he_il/audio/test.tar.gz || exit 1
# Models (licences: hebrew-accuracy-design.md). Only the engines being run are fetched.
want() { case " $ENGINES " in *" $1 "*) return 0;; esac; return 1; }
want zipformer && fetch ivrit-ai/zipformer2-66m-streaming-he ee769a2 "$WORK/models/zipformer2-66m-streaming-he-int8" \
  sherpa-onnx/encoder.int8.onnx sherpa-onnx/decoder.int8.onnx sherpa-onnx/joiner.int8.onnx sherpa-onnx/tokens.txt
want nemotron && fetch csukuangfj2/sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-1120ms-int8-2026-06-11 cba1c96 \
  "$WORK/models/nemotron-3.5-asr-streaming-0.6b-1120ms-int8" encoder.int8.onnx decoder.int8.onnx joiner.int8.onnx tokens.txt
want parakeet-he && fetch thewh1teagle/parakeet-tdt-0.6b-v3-he 0037204 "$WORK/models/parakeet-tdt-0.6b-v3-he" config.json \
  generation_config.json processor_config.json tokenizer.json tokenizer_config.json model.safetensors
want whisper-ivrit && fetch ivrit-ai/whisper-large-v3-turbo f33172a "$WORK/models/whisper-large-v3-turbo-ivrit" config.json \
  generation_config.json added_tokens.json merges.txt normalizer.json preprocessor_config.json special_tokens_map.json \
  tokenizer.json tokenizer_config.json vocab.json model.safetensors

[ -f "$WORK/shards/he/index.json" ] || "$PY" -m edacc_eval.cli fleurs-shards --corpus "$WORK/corpus" \
  --out "$WORK/shards" --languages he || exit 1
(cd "$REPO/Packages/EngineEval" && swift build -c release) || { echo "swift build failed"; exit 1; }

rescore() {
  "$PY" -m edacc_eval.cli report-hebrew --shards "$WORK/shards" --results "$WORK/results" \
    --out "$WORK/report/hebrew-accuracy-comparison.md" --json-out "$WORK/report/hebrew-accuracy.json" \
    || echo "re-score failed"
}

failed=0
model_dir() { case $1 in zipformer) echo zipformer2-66m-streaming-he-int8;; nemotron) echo nemotron-3.5-asr-streaming-0.6b-1120ms-int8;;
  parakeet-he) echo parakeet-tdt-0.6b-v3-he;; whisper-ivrit) echo whisper-large-v3-turbo-ivrit;; esac; }
shards=$("$PY" -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["shards"]))' "$WORK/shards/he/index.json")
for e in $ENGINES; do  # engine by engine, so a model can be deleted once it has done every shard (HE_DELETE_MODELS=1)
  ok=1
  for shard in $shards; do
    dir="$WORK/shards/he/$shard"
    echo "$(date '+%F %T') $e $shard"
    if [ "$e" = apple-dictation ]; then
      nice -n 15 "$BIN" run --shard-dir "$dir" --results "$WORK/results/he-$shard-swift.jsonl" \
        --engines apple-dictation --locale he-IL --status "$WORK/status-engine.json" || ok=0
    else
      nice -n 15 "$PY" -m edacc_eval.cli hebrew-run --engine "$e" --shard-dir "$dir" \
        --results "$WORK/results/he-$shard-$e.jsonl" --models-dir "$WORK/models" --threads "$THREADS" \
        --status "$WORK/status-engine.json" || ok=0
    fi
  done
  [ $ok = 1 ] || failed=1
  if [ $ok = 1 ] && [ "${HE_DELETE_MODELS:-0}" = 1 ] && [ "$e" != apple-dictation ]; then
    rm -rf "${WORK:?}/models/$(model_dir "$e")"
  fi
  rescore
done
rescore
echo "$(date '+%F %T') HEBREW-DRIVER-DONE (errors: $failed)"
exit $failed
