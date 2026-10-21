#!/bin/bash
# M4 Mac mini: the engine accuracy cycles (#145). A sequential loop, one shard after another:
#   fetch shard (rsync --checksum) -> run every Apple engine on every clip -> push results -> re-score on the
#   2012 mini -> copy the report back -> delete the shard audio -> next.
# Resumable: engine-eval skips every (clip, engine, model, repeat) already in the shard's result file, and a
# finished shard leaves a done marker. Start it with m4-launch.sh (nohup + exported settings), not directly.
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

REMOTE="${EVAL_REMOTE:-mac-mini-2012}"
WORK="${EVAL_WORK:-$HOME/edacc-eval}"
REPO="${EVAL_REPO:?EVAL_REPO must point at the clarity-captions worktree}"
REPEATS="${EVAL_REPEATS:-1}"
FIRST="${EVAL_FIRST:-1}"
MAX_SHARDS="${EVAL_MAX_SHARDS:-1}"
ENGINES="${EVAL_ENGINES:-apple,parakeet-v2,parakeet-ultra,whisperkit}"
BIN="$REPO/Packages/EngineEval/.build/release/engine-eval"
STATUS="$WORK/status.txt"
mkdir -p "$WORK/shards" "$WORK/results" "$WORK/done" "$WORK/report" "$WORK/logs"

status() {  # stage line for the visible window; engine progress lives in status-engine.json
  printf 'Engine accuracy test (#145)\nShard %s of %s  (this run: %s of %s, repeats %s)\nStage: %s\nUpdated: %s\n' \
    "$1" "$TOTAL" "$2" "$COUNT" "$REPEATS" "$3" "$(date '+%Y-%m-%d %H:%M:%S')" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
}

TOTAL=$(ssh "$REMOTE" 'cat edacc-eval/shards/index.json' | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["n_shards"])') \
  || { echo "cannot read shard index from $REMOTE"; exit 1; }
LAST=$(( FIRST + MAX_SHARDS - 1 )); [ "$LAST" -gt "$TOTAL" ] && LAST=$TOTAL
COUNT=$(( LAST - FIRST + 1 ))
echo "$(date '+%F %T') driver start: shards $FIRST..$LAST of $TOTAL, repeats $REPEATS, engines $ENGINES"

[ -x "$BIN" ] || (cd "$REPO/Packages/EngineEval" && swift build -c release) || { echo "build failed"; exit 1; }

i=0
for k in $(seq "$FIRST" "$LAST"); do
  i=$(( i + 1 ))
  name=$(printf 'shard-%03d' "$k")
  marker="$WORK/done/$name.r$REPEATS.$(echo "$ENGINES" | tr ',' '+')"
  if [ -e "$marker" ]; then echo "$name already done"; continue; fi

  status "$k" "$i" "fetching $name from $REMOTE"
  rsync -a --checksum "$REMOTE:edacc-eval/shards/$name/" "$WORK/shards/$name/" || { echo "fetch $name failed"; exit 1; }

  status "$k" "$i" "running engines on $name"
  "$BIN" run --shard-dir "$WORK/shards/$name" --results "$WORK/results/apple-$name.jsonl" \
    --engines "$ENGINES" --repeats "$REPEATS" --models-dir "$WORK/models" --status "$WORK/status-engine.json"
  rc=$?

  status "$k" "$i" "pushing results and re-scoring"
  rsync -a "$WORK/results/apple-$name.jsonl" "$REMOTE:edacc-eval/results/" || echo "push results failed (kept locally)"
  ssh "$REMOTE" 'edacc-eval/tool/linux-score.sh' || echo "re-score failed"
  rsync -a "$REMOTE:edacc-eval/report/engine-accuracy-comparison.md" "$WORK/report/" \
    && cp "$WORK/report/engine-accuracy-comparison.md" "$REPO/docs/perf/engine-accuracy-comparison.md"

  rm -rf "$WORK/shards/$name"
  if [ "$rc" -eq 0 ]; then touch "$marker"; else echo "$name finished with engine errors (rc $rc); rerun resumes it"; fi
  echo "$(date '+%F %T') $name cycle done (rc $rc)"
done
status "$LAST" "$COUNT" "FINISHED"
echo "$(date '+%F %T') DRIVER-DONE"
