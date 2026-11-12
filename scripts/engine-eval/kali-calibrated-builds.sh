#!/bin/bash
# The 2012 Mac mini (Kali, Linux): the torch half of the #272 builds, everything that needs no Mac. Fisher importance,
# k-means, the fp16 Core ML export and the exact palettize packing run here; each build ends as a staged
# <name>.Encoder.mlpackage that the M4 compiles and assembles (calibrated_ultra.py assemble), then scores.
# Workload split (owner, 2026-11-09): the M4 is short of disk and memory; this box has 100+ GB and its own RAM.
# Layout: ~/edacc-272/{code (rsync of scripts/engine-eval), convert/{mobius,ultra.nemo}, calib-272, sensitivity.json,
#         staged}. Resumable: a build whose staged package exists is skipped.
# Start: nohup nice -n 10 ~/edacc-272/code/kali-calibrated-builds.sh >> ~/edacc-272/builds.log 2>&1 &
set -uo pipefail
W="$HOME/edacc-272"
CPY="$W/convert/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml/.venv/bin/python"
STAGED="$W/staged"
# name|calibrated_ultra.py build arguments
BUILDS="${KALI_BUILDS:-ultra-t4k|--bits 4;ultra-skm4|--bits 4 --calibrated --fisher-clips 96;ultra-mix46|--target-bits 4.75;ultra-mix46-skm|--target-bits 4.75 --calibrated --fisher-clips 96}"
mkdir -p "$STAGED"
export PYTHONPATH="$W/code"
IFS=';' read -ra BL <<< "$BUILDS"
for spec in "${BL[@]}"; do
  name="${spec%%|*}"; args="${spec#*|}"
  [ -e "$STAGED/$name.variant.json" ] && { echo "$name: already staged"; continue; }
  free=$(df -BG --output=avail "$HOME" | tail -1 | tr -dc 0-9)
  [ "$free" -ge 10 ] || { echo "LOW-DISK: $free GB free before $name"; exit 3; }
  echo "$(date '+%F %T') BUILD-START $name"
  # shellcheck disable=SC2086
  "$CPY" "$W/code/calibrated_ultra.py" build --name "$name" $args --no-compile --check-calib 0 \
    --nemo "$W/convert/ultra.nemo" --convert "$W/convert" --calib "$W/calib-272" --sensitivity "$W/sensitivity.json" \
    --work "$W/work" --out "$STAGED" --fisher-cache "$W/fisher-272.pt" --threads 8 --workers 6 \
    || { echo "BUILD-FAILED $name"; exit 1; }
  echo "$(date '+%F %T') BUILD-STAGED $name"
done
echo "$(date '+%F %T') KALI-BUILDS-DONE"
