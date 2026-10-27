#!/bin/bash
# Apple's Translation framework on FLORES-200 devtest and the EdAcc caption lines, for every installed English->X
# pair (#159 follow-up). One language at a time so the timing isn't shared. Sets come from
# `python -m translation_eval.cli build-languages`; results land in ~/translation-eval/results-apple/en-<code>.
# Usage: scripts/engine-eval/translation-apple-languages.sh [code ...]   (default: every folder in sets-apple)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SETS="$HOME/translation-eval/sets-apple"
OUT="$HOME/translation-eval/results-apple"
swift build --package-path "$ROOT/Packages/EngineEval" --product translation-eval >/dev/null
BIN="$(swift build --package-path "$ROOT/Packages/EngineEval" --show-bin-path)/translation-eval"
codes=("$@")
if [ ${#codes[@]} -eq 0 ]; then
  for d in "$SETS"/en-*; do codes+=("${d##*/en-}"); done
fi
for code in "${codes[@]}"; do
  mkdir -p "$OUT/en-$code"
  echo "== en-$code $(date +%T)"
  "$BIN" --sets "$SETS/en-$code" --target "$code" --results "$OUT/en-$code/apple.jsonl" --repeats 2
done
echo "== done $(date +%T)"
