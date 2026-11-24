#!/bin/bash
# Car-call set (#303), end to end and silent: fetch the source clips, build the set, run Parakeet Ultra and Apple
# SpeechAnalyzer on the files, score each voice. Nothing is played or recorded. See car_call/README.md.
#   CC_REPO=~/Developer/cc-303 scripts/engine-eval/car_call/run.sh
set -euo pipefail
REPO="${CC_REPO:?CC_REPO must point at the clarity-captions worktree}"
CACHE="${CC_CACHE:-$HOME/Library/Caches/seal-car-call}"
PY="${CC_PYTHON:-$HOME/.agents/venv/bin/python}"            # needs numpy + scipy
REMOTE="${CC_REMOTE:-mac-mini-2012}"                         # holds edacc-eval/shards/shard-001
MANIFEST="${CC_MANIFEST:-$HOME/edacc-eval/manifests/shard-001/manifest.jsonl}"
MODELS="${CC_MODELS:-$HOME/edacc-eval/models}"               # fluidaudio/parakeet-ultra
PAIRS="${CC_PAIRS:-30}"; SNRS="${CC_SNRS:-20,10,5,0}"; SEED="${CC_SEED:-303}"
ENGINES="${CC_ENGINES:-parakeet-ultra,apple}"
BIN="$REPO/Packages/EngineEval/.build/release/engine-eval"
cd "$REPO/scripts/engine-eval"

mkdir -p "$CACHE/src/audio" "$CACHE/results"
cp "$MANIFEST" "$CACHE/src/manifest.jsonl"
"$PY" -m car_call.build --source "$CACHE/src" --out "$CACHE/set" --pairs "$PAIRS" --seed "$SEED" --select-only \
  | "$PY" -c 'import json,sys; print("\n".join(sorted({f for l in sys.stdin for f in json.loads(l).values()})))' \
  > "$CACHE/files.txt"
rsync -a --files-from="$CACHE/files.txt" "$REMOTE:edacc-eval/shards/shard-001/" "$CACHE/src/"
"$PY" -m car_call.build --source "$CACHE/src" --out "$CACHE/set" --pairs "$PAIRS" --snrs "$SNRS" --seed "$SEED"

[ -x "$BIN" ] || (cd "$REPO/Packages/EngineEval" && swift build -c release)
"$BIN" run --shard-dir "$CACHE/set" --results "$CACHE/results/car-call.jsonl" --engines "$ENGINES" \
  --models-dir "$MODELS" --status "$CACHE/status-engine.json"

"$PY" -m car_call.score --set "$CACHE/set" --results "$CACHE/results/car-call.jsonl" \
  --out "$CACHE/car-call-table.md" --json-out "$CACHE/car-call.json"
