#!/bin/bash
# Usage on the M4 mini: m4-launch.sh FIRST MAX_SHARDS REPEATS [ENGINES]
# Exports the run's settings and starts m4-driver.sh with nohup so it survives the session, then opens a
# Terminal window on the Mini that shows progress and closes itself when the run ends.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
HERE="$(cd "$(dirname "$0")" && pwd)"
export EVAL_REPO="$(cd "$HERE/../.." && pwd)"
export EVAL_WORK="$HOME/edacc-eval"
export EVAL_FIRST="$1" EVAL_MAX_SHARDS="$2" EVAL_REPEATS="$3"
export EVAL_ENGINES="${4:-apple,parakeet-v2,parakeet-ultra,whisperkit}"
mkdir -p "$EVAL_WORK/logs"
rm -f "$EVAL_WORK/status.txt"
nohup "$HERE/m4-driver.sh" >> "$EVAL_WORK/logs/driver.log" 2>&1 < /dev/null &
echo "driver pid $!"
cp "$HERE/m4-watch.sh" "$EVAL_WORK/engine-eval-watch.command"
chmod +x "$EVAL_WORK/engine-eval-watch.command"
open -a Terminal "$EVAL_WORK/engine-eval-watch.command"
