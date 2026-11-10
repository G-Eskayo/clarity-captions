#!/bin/bash
# Speaker scoring on the 2012 mini (Kali), per the owner's workload split (2026-11-09): replays (hypotheses) are made
# on the M4, scoring is CPU-only and runs there, with the scorer from this repo so both sides run the same code.
# Copies scripts/engine-eval/speaker_eval and the given input folders over, runs one speaker_eval module with
# python3 -I, and copies its out/ folder back.
#   scripts/engine-eval/kali-speaker-score.sh JOB LOCAL_OUT MODULE [--sync NAME=LOCAL_DIR]... -- ARGS...
# In ARGS, @NAME is the remote copy of a synced folder, @OUT the remote output folder. Example:
#   kali-speaker-score.sh calib ~/sortformer-271/report fidelity --sync results=~/sortformer-271/calib -- \
#     --results @results --rttm-dir @ami/setup/only_words/rttms/dev ... --out-md @OUT/calibration.md
# (@ami and @chime6 are the corpora already on the 2012 mini: ~/ami-eval, ~/chime6-eval.)
set -euo pipefail
REMOTE="${EVAL_REMOTE:-mac-mini-2012}"
JOB="${1:?job name}"; LOCAL_OUT="${2:?local output folder}"; MODULE="${3:?speaker_eval module}"; shift 3
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="speaker-271/$JOB"
syncs=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
  [ "$1" = "--sync" ] || { echo "expected --sync NAME=DIR or --, got $1"; exit 2; }
  syncs+=("$2"); shift 2
done
[ "${1:-}" = "--" ] && shift
ssh "$REMOTE" "mkdir -p '$BASE/code' '$BASE/out'"
rsync -a --delete --exclude __pycache__ "$HERE/speaker_eval" "$REMOTE:$BASE/code/"
for s in "${syncs[@]+"${syncs[@]}"}"; do
  name="${s%%=*}"; dir="${s#*=}"
  rsync -a --delete "$dir/" "$REMOTE:$BASE/$name/"
done
args=()
for x in "$@"; do
  x="${x//@OUT/\$HOME/$BASE/out}"; x="${x//@ami/\$HOME/ami-eval}"; x="${x//@chime6/\$HOME/chime6-eval}"
  for s in "${syncs[@]+"${syncs[@]}"}"; do name="${s%%=*}"; x="${x//@$name/\$HOME/$BASE/$name}"; done
  args+=("\"$x\"")
done
ssh "$REMOTE" bash -s <<EOF
set -euo pipefail
cd "\$HOME/$BASE"
python3 -I -c 'import runpy, sys; sys.path.insert(0, "code"); sys.argv = ["speaker_eval.$MODULE"] + sys.argv[1:]; runpy.run_module("speaker_eval.$MODULE", run_name="__main__")' ${args[*]}
EOF
mkdir -p "$LOCAL_OUT"
rsync -a "$REMOTE:$BASE/out/" "$LOCAL_OUT/"
