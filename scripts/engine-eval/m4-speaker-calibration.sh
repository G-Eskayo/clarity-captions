#!/bin/bash
# M4 Mac mini: replay compressed Sortformer builds and fp16 on CALIBRATION audio, to choose one build per bit width
# (#271 step 2, speaker_eval/fidelity.py). Never touches test audio: every recording is checked against the frozen
# split's calibration list first. Each recording is fetched once from the 2012 mini, replayed by every build (one
# process per run, empty line list: only the model's segments matter here), then deleted. Resumable.
#   EVAL_REPO=<worktree> BUILDS="fp16=/path/A.mlmodelc pal8=/path/B.mlmodelc ..." RECS="ES2011a ..." \
#     OUT=~/sortformer-271/calib scripts/engine-eval/m4-speaker-calibration.sh
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

REMOTE="${EVAL_REMOTE:-mac-mini-2012}"
REPO="${EVAL_REPO:?EVAL_REPO must point at the clarity-captions worktree}"
BUILDS="${BUILDS:?BUILDS must list label=model pairs}"
RECS="${RECS:?RECS must list calibration recordings}"
OUT="${OUT:?OUT must name the results folder}"
PY="${EVAL_PY:-$HOME/.agents/venv/bin/python}"
BIN="$REPO/Packages/EngineEval/.build/release/engine-eval"
WORK="$OUT/.audio"
mkdir -p "$OUT" "$WORK"

[ -x "$BIN" ] || { echo "build engine-eval first (swift build -c release --product engine-eval)"; exit 1; }
(cd "$REPO/scripts/engine-eval" && "$PY" -c "
import sys; from speaker_eval import split
sp = split.load(set_name='ami')
for r in sys.argv[1:]: sp.require_calibration(r)
" $RECS) || { echo "refusing: not all of RECS are calibration recordings"; exit 2; }
echo '[]' > "$OUT/.no-lines.json"

errors=0
for rec in $RECS; do
  need=0
  for b in $BUILDS; do [ -s "$OUT/$rec.${b%%=*}.json" ] || need=1; done
  [ "$need" -eq 1 ] || { echo "$rec done"; continue; }
  rsync -a "$REMOTE:ami-eval/audio/$rec.wav" "$WORK/" || { echo "$rec: fetch failed"; errors=$((errors+1)); continue; }
  for b in $BUILDS; do
    label="${b%%=*}"; model="${b#*=}"; out="$OUT/$rec.$label.json"
    [ -s "$out" ] && continue
    "$BIN" speakers --audio "$WORK/$rec.wav" --phrases "$OUT/.no-lines.json" --model "$model" --model-label "$label" \
      --recording "$rec" --out "$out" || { echo "$rec $label failed"; errors=$((errors+1)); }
  done
  rm -f "$WORK/$rec.wav"
done
echo "$(date '+%F %T') calibration finished, $errors error(s)"
exit $(( errors > 0 ))
