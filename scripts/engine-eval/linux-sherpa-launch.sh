#!/usr/bin/env bash
# Usage on the 2012 mini: linux-sherpa-launch.sh FIRST LAST REPEATS [THREADS]
# Exports the settings and starts the driver with nohup so it survives the ssh session.
set -euo pipefail
export PATH=/usr/bin:/bin
export SHERPA_FIRST="$1" SHERPA_LAST="$2" SHERPA_REPEATS="$3" SHERPA_THREADS="${4:-4}"
ROOT="$HOME/edacc-eval"
mkdir -p "$ROOT/logs"
nohup nice -n 15 "$ROOT/tool/linux-sherpa-driver.sh" >> "$ROOT/logs/sherpa.log" 2>&1 < /dev/null &
echo "sherpa driver pid $!"
