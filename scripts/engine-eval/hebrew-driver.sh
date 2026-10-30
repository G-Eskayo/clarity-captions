#!/bin/bash
# The Hebrew engine test (#201), one command, on an Apple-silicon Mac (macOS 26):
#   EVAL_REPO=<clarity-captions checkout> scripts/engine-eval/hebrew-driver.sh
# Fetches the pinned test sets (FLEURS he; ivrit.ai eval-d1 and eval-whatsapp, gated: needs a Hugging Face token whose
# account accepted ivrit.ai's terms, from $HF_TOKEN or ~/.cache/huggingface/token) and cuts them into shards, then
# engine by engine fetches the pinned model, runs it over every shard of every set and rewrites the report. Engines:
# Apple DictationTranscriber he-IL, the ivrit.ai zipformer, Nemotron 3.5 zero-shot, Parakeet-He and ivrit.ai Whisper
# turbo. Every engine runs locally; no cloud service, no paid API.
# Resumable: each engine skips clips already in the shard's result file. Method: docs/perf/hebrew-accuracy-design.md.
# HE_DELETE_MODELS=1 deletes each model once it has done every shard (one model on disk at a time);
# HE_DELETE_AUDIO=1 deletes the downloaded audio (shard WAVs, parquet, tarball) once every engine has scored it.
# Needs the Hebrew venv (sherpa-onnx 2.0.1, transformers, torch, librosa, scipy, soundfile, pyarrow, rapidfuzz).
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin

REPO="${EVAL_REPO:?EVAL_REPO must point at the clarity-captions checkout}"
WORK="${HE_WORK:-$HOME/hebrew-eval}"            # corpus, shards, models, results, venv: outside the repo
PY="${HE_PY:-$WORK/venv/bin/python}"
ENGINES="${HE_ENGINES:-apple-dictation zipformer nemotron parakeet-he whisper-ivrit}"
SETS="${HE_SETS:-he eval-d1 eval-whatsapp}"       # shard sets: FLEURS he, then ivrit.ai's conversation and voice notes
THREADS="${HE_THREADS:-8}"
BIN="$REPO/Packages/EngineEval/.build/release/engine-eval"
export PYTHONPATH="$REPO/scripts/engine-eval"
mkdir -p "$WORK/corpus/he_il" "$WORK/corpus/eval-d1" "$WORK/corpus/eval-whatsapp" "$WORK/models" "$WORK/results" "$WORK/report" "$WORK/logs"

TOKEN="${HF_TOKEN:-$(cat "$HOME/.cache/huggingface/token" 2>/dev/null)}"
fetch() {  # fetch <repo> <revision> <dir> <file>...: pinned revisions; each model in its own folder
  local repo=$1 rev=$2 dir=$3; shift 3
  local auth=()
  [ -n "$TOKEN" ] && auth=(-H "Authorization: Bearer $TOKEN")  # gated ivrit.ai sets; harmless for open repos
  mkdir -p "$dir"
  for f in "$@"; do
    local out="$dir/$(basename "$f")"
    [ -s "$out" ] && continue
    curl -sfL --retry 3 "${auth[@]}" -o "$out.part" "https://huggingface.co/$repo/resolve/$rev/$f" && mv "$out.part" "$out" \
      || { echo "fetch failed: $repo $f"; return 1; }
  done
  echo "$repo@$rev" > "$dir/SOURCE"
}

wanted() { case " $2 " in *" $1 "*) return 0;; esac; return 1; }
# Data (licences: hebrew-accuracy-design.md). Not needed again once a set's shards exist.
# FLEURS he test split, CC BY 4.0, the commit #158 pinned.
if wanted he "$SETS" && [ ! -f "$WORK/shards/he/index.json" ]; then
  fetch datasets/google/fleurs 70bb2e8 "$WORK/corpus/he_il" data/he_il/test.tsv data/he_il/audio/test.tar.gz || exit 1
  "$PY" -m edacc_eval.cli fleurs-shards --corpus "$WORK/corpus" --out "$WORK/shards" --languages he || exit 1
fi
# ivrit.ai eval-d1 (conversation) and eval-whatsapp (voice notes), gated, at the revisions pinned in ivrit.py.
for set in eval-d1 eval-whatsapp; do
  wanted "$set" "$SETS" && [ ! -f "$WORK/shards/$set/index.json" ] || continue
  read -r repo rev file < <("$PY" -c 'import sys; from edacc_eval.ivrit import SETS; s = SETS[sys.argv[1]]
print(s.repo, s.revision, s.file)' "$set")
  fetch "datasets/$repo" "$rev" "$WORK/corpus/$set" "$file" \
    || { echo "$set: gated; accept ivrit.ai's terms on Hugging Face and save a token"; exit 1; }
  "$PY" -m edacc_eval.cli ivrit-shards --parquet "$WORK/corpus/$set/$(basename "$file")" --out "$WORK/shards" \
    --set "$set" || exit 1
done
# Models, fetched one engine at a time just before it runs, so with HE_DELETE_MODELS=1 only one is ever on disk.
fetch_model() {
  case $1 in
    zipformer) fetch ivrit-ai/zipformer2-66m-streaming-he ee769a2 "$WORK/models/zipformer2-66m-streaming-he-int8" \
      sherpa-onnx/encoder.int8.onnx sherpa-onnx/decoder.int8.onnx sherpa-onnx/joiner.int8.onnx sherpa-onnx/tokens.txt;;
    nemotron) fetch csukuangfj2/sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-1120ms-int8-2026-06-11 cba1c96 \
      "$WORK/models/nemotron-3.5-asr-streaming-0.6b-1120ms-int8" encoder.int8.onnx decoder.int8.onnx joiner.int8.onnx \
      tokens.txt;;
    parakeet-he) fetch thewh1teagle/parakeet-tdt-0.6b-v3-he 0037204 "$WORK/models/parakeet-tdt-0.6b-v3-he" config.json \
      generation_config.json processor_config.json tokenizer.json tokenizer_config.json model.safetensors;;
    whisper-ivrit) fetch ivrit-ai/whisper-large-v3-turbo f33172a "$WORK/models/whisper-large-v3-turbo-ivrit" \
      config.json generation_config.json added_tokens.json merges.txt normalizer.json preprocessor_config.json \
      special_tokens_map.json tokenizer.json tokenizer_config.json vocab.json model.safetensors;;
  esac
}
(cd "$REPO/Packages/EngineEval" && swift build -c release) || { echo "swift build failed"; exit 1; }

rescore() {
  "$PY" -m edacc_eval.cli report-hebrew --shards "$WORK/shards" --results "$WORK/results" \
    --out "$WORK/report/hebrew-accuracy-comparison.md" --json-out "$WORK/report/hebrew-accuracy.json" \
    || echo "re-score failed"
}

failed=0
model_dir() { case $1 in zipformer) echo zipformer2-66m-streaming-he-int8;; nemotron) echo nemotron-3.5-asr-streaming-0.6b-1120ms-int8;;
  parakeet-he) echo parakeet-tdt-0.6b-v3-he;; whisper-ivrit) echo whisper-large-v3-turbo-ivrit;; esac; }
shards_of() { "$PY" -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["shards"]))' "$WORK/shards/$1/index.json"; }
for e in $ENGINES; do  # engine by engine, so a model can be deleted once it has done every shard (HE_DELETE_MODELS=1)
  ok=1
  [ "$e" = apple-dictation ] || fetch_model "$e" || { failed=1; continue; }
  for set in $SETS; do
  for shard in $(shards_of "$set"); do
    dir="$WORK/shards/$set/$shard"
    tag=$([ "$set" = he ] && echo "he-$shard" || echo "$set-$shard")  # FLEURS keeps #215's result file names
    echo "$(date '+%F %T') $e $set $shard"
    if [ "$e" = apple-dictation ]; then
      nice -n 15 "$BIN" run --shard-dir "$dir" --results "$WORK/results/$tag-swift.jsonl" \
        --engines apple-dictation --locale he-IL --status "$WORK/status-engine.json" || ok=0
    else
      nice -n 15 "$PY" -m edacc_eval.cli hebrew-run --engine "$e" --shard-dir "$dir" \
        --results "$WORK/results/$tag-$e.jsonl" --models-dir "$WORK/models" --threads "$THREADS" \
        --status "$WORK/status-engine.json" || ok=0
    fi
  done
  done
  [ $ok = 1 ] || failed=1
  if [ $ok = 1 ] && [ "${HE_DELETE_MODELS:-0}" = 1 ] && [ "$e" != apple-dictation ]; then
    rm -rf "${WORK:?}/models/$(model_dir "$e")"
  fi
  rescore
done
rescore
if [ $failed = 0 ] && [ "${HE_DELETE_AUDIO:-0}" = 1 ]; then  # scored by every engine: keep manifests, drop the audio
  for set in $SETS; do rm -rf "${WORK:?}/shards/$set"/shard-*/audio; done
  rm -rf "${WORK:?}/corpus"
fi
echo "$(date '+%F %T') HEBREW-DRIVER-DONE (errors: $failed)"
exit $failed
