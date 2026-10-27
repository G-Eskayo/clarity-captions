#!/bin/bash
# Run every OPUS-MT model (CTranslate2 int8) over every pair's sets (#159). Resumable: rerun to continue.
# Usage: translation-open-models.sh [pair ...]   (default: en-es en-fr en-de)
# EVAL_SETS_ROOT overrides the sets folder (e.g. one holding only the reference sets, skipping the caption-line pass).
set -uo pipefail
cd "$(dirname "$0")"
PY="${EVAL_PY:-$HOME/translation-eval/venv/bin/python}"
ROOT="${EVAL_ROOT:-$HOME/translation-eval}"
PAIRS=("${@:-en-es en-fr en-de}")
for pair in ${PAIRS[@]}; do
  sets="${EVAL_SETS_ROOT:-$ROOT/sets}/$pair"
  for spec in "opus-mt:opus-mt-$pair" "opus-mt-big:opus-mt-tc-big-$pair"; do
    engine="${spec%%:*}"; model="${spec#*:}"; dir="$ROOT/models/$model-ct2"
    [ -d "$dir" ] || { echo "skip $model (no CTranslate2 folder)"; continue; }
    mkdir -p "$ROOT/results/$pair"
    nice -n 10 "$PY" -m translation_eval.cli ct2 --sets "$sets" --model "$dir" --hf-model "$dir" \
      --engine "$engine" --results "$ROOT/results/$pair/$engine.jsonl" 2>&1 | grep -v -i warn
  done
done
