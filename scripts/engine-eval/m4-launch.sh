#!/bin/bash
# Usage on the M4 mini: m4-launch.sh FIRST MAX_SHARDS REPEATS [ENGINES]
# Optional: EVAL_SHERPA=1 (with EVAL_SHERPA_FIRST/LAST/REPEATS) makes the M4 take sherpa-onnx shards from the
# shared claim queue after its own engines finish.
# Exports the run's settings and starts m4-driver.sh with nohup so it survives the session, then opens a
# Terminal window on the Mini that shows progress and closes itself when the run ends.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
HERE="$(cd "$(dirname "$0")" && pwd)"
export EVAL_REPO="$(cd "$HERE/../.." && pwd)"
export EVAL_WORK="$HOME/edacc-eval"
export EVAL_FIRST="$1" EVAL_MAX_SHARDS="$2" EVAL_REPEATS="$3"
export EVAL_ENGINES="${4:-apple,parakeet-v2,parakeet-ultra}"  # WhisperKit dropped after shard 1
export EVAL_SHERPA="${EVAL_SHERPA:-0}" EVAL_SHERPA_FIRST="${EVAL_SHERPA_FIRST:-1}" EVAL_SHERPA_LAST="${EVAL_SHERPA_LAST:-32}"
export EVAL_SHERPA_REPEATS="${EVAL_SHERPA_REPEATS:-$3}" EVAL_SHERPA_THREADS="${EVAL_SHERPA_THREADS:-8}"
mkdir -p "$EVAL_WORK/logs"
rm -f "$EVAL_WORK/status.txt"
# EVAL_DRIVER picks the loop: m4-driver.sh (the cycles, default) or m4-shard-extras.sh (one shard's extras).
# Low priority (nice +15) so dashboard merge gates and interactive work win the CPU.
nohup nice -n 15 "$HERE/${EVAL_DRIVER:-m4-driver.sh}" >> "$EVAL_WORK/logs/driver.log" 2>&1 < /dev/null &
echo "driver pid $!"
cp "$HERE/m4-watch.sh" "$EVAL_WORK/engine-eval-watch.command"
chmod +x "$EVAL_WORK/engine-eval-watch.command"
open -a Terminal "$EVAL_WORK/engine-eval-watch.command"
