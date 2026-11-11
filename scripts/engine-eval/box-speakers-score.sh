#!/bin/bash
# 2012 box (#160): once the engine queue is done, score every engine on both test sets with the #276 scorer, and the
# paired difference against the app's Core ML fp16 baseline (speaker_eval.compare, #271 step 2), using #276's own
# fp16 result files (copied to baseline/<set>/, linked beside the engine results in compare/<set>/).
# WAIT=1 waits for "queue finished" in logs/queue.log first (checks once a minute, on the box).
#   nohup env WAIT=1 bin/box-speakers-score.sh > logs/score.log 2>&1 &
set -uo pipefail
ROOT="${ROOT:-$HOME/speaker-160}"
cd "$ROOT/code" || exit 2
if [ "${WAIT:-0}" = 1 ]; then
  until grep -q "queue finished" "$ROOT/logs/queue.log" 2>/dev/null; do sleep 60; done
fi
PY=("$ROOT/venv/bin/python" -I "$ROOT/bin/py")
OUT="$ROOT/scored"; mkdir -p "$OUT"
status=0
for set in chime6 ami; do
  ref=(--rttm-dir "$ROOT/ref/$set/rttm" --uem-dir "$ROOT/ref/$set/uem")
  for label in ${LABELS:-recogment-v2 sherpa-wespeaker}; do
    nice -n 5 "${PY[@]}" speaker_eval.cli score --set "$set" --model "$label" --results "$ROOT/results/$set" "${ref[@]}" \
      --out-md "$OUT/$label-$set.md" --out-json "$OUT/$label-$set.json" || status=1
    cmp="$ROOT/compare/$set"; mkdir -p "$cmp"
    ln -sf "$ROOT"/baseline/"$set"/*.fp16.r1.json "$ROOT"/results/"$set"/*."$label".r1.json "$cmp"/
    nice -n 5 "${PY[@]}" speaker_eval.compare --set "$set" --base fp16 --model "$label" --results "$cmp" "${ref[@]}" \
      --out-json "$OUT/$label-$set.paired.json" --out-md "$OUT/$label-$set.paired.md" > /dev/null || status=1
  done
done
echo "$(date '+%F %T') scoring finished (status $status)"
exit $status
