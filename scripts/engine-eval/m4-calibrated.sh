#!/bin/bash
# M4 Mac mini: calibrated low-bit Parakeet Ultra (#272 "Parakeet Ultra smaller with no loss"), steps 1-3, one
# sequential chain, resumable at every step.
#   1. layer sensitivity on the held-out calibration split (calibrated_ultra.py sensitivity)
#   2. the builds in $BUILDS (calibrated_ultra.py build), one fp16 export each, deleted once packed
#   3. decoder + joint palettized onto the best encoder build ($DEC_FROM), when set
#   4. every EdAcc shard streamed from the 2012 mini (it keeps them), one at a time: copy, run every new build on it,
#      delete; 6-bit runs shard 1 again first so speed is compared in the same hour; machine load every 30 s
#   5. live latency (shard 1) and memory, sizes, and the held-out report (calibration speakers never scored)
# Needs: the 2012 mini running kali-calibrated-builds.sh (it holds ultra.nemo, the calibration clips and the builds'
#        torch half), ~/edacc-eval/manifests (EdAcc manifests), the mobius env for compiling, ssh to mac-mini-2012.
# Start: EVAL_REPO=<worktree> nohup nice -n 15 scripts/engine-eval/m4-calibrated.sh >> ~/edacc-eval/logs/272.log 2>&1 &
set -uo pipefail
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PYTORCH_ENABLE_MPS_FALLBACK=1
WORK="${EVAL_WORK:-$HOME/edacc-eval}"
REPO="${EVAL_REPO:?}"
HERE="$REPO/scripts/engine-eval"
C="$WORK/convert"
CPY="$C/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml/.venv/bin/python"
PY="$WORK/venv/bin/python"
KALI="${EVAL_SHARD_HOST:-mac-mini-2012}"
KALI_SHARDS="${EVAL_SHARD_PATH:-edacc-eval/shards}"
SPLIT="$REPO/docs/perf/edacc-heldout-split.json"
R="${EVAL_RESULTS:-$WORK/results-272}"   # one folder per scoring run: shard markers are per run
S="$WORK/shard-272"                 # one shard at a time
SENS="$R/sensitivity.json"
BIN="$REPO/Packages/EngineEval/.build/release/engine-eval"
SIZES="$R/sizes.json"
LOAD="$R/load.tsv"
REF="local:ultra-pal6"
# name|calibrated_ultra.py build arguments
BUILDS="${EVAL_BUILDS:-ultra-skm4|--bits 4 --calibrated;ultra-mix46|--target-bits 4.75;ultra-mix46-skm|--target-bits 4.75 --calibrated}"
DEC_FROM="${EVAL_DEC_FROM:-}"       # e.g. ultra-mix46-skm: also build <it>-dec6 with decoder + joint at 6 bits
export PYTHONPATH="$HERE"
STATUS="$WORK/status-272.txt"
status() { printf 'Calibrated Ultra (#272)\nStage: %s\nUpdated: %s\n' "$1" "$(date '+%F %T')" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"; }
mkdir -p "$R/latency" "$R/memory" "$WORK/models/variants"
# The Mini runs other sessions too; never be the job that fills its disk. Paused runs resume where they stopped.
MIN_FREE_GB="${EVAL_MIN_FREE_GB:-3}"
guard() { local f; f=$(df -g / | awk 'NR==2{print $4}')
  [ "$f" -ge "$MIN_FREE_GB" ] || { status "PAUSED: $f GiB free (< $MIN_FREE_GB) before $1"; echo "LOW-DISK pause before $1"; exit 3; }; }
for need in "$WORK/manifests/index.json" "$CPY" "$SPLIT"; do
  [ -e "$need" ] || { echo "missing $need"; exit 1; }
done

[ -s "$LOAD" ] || printf 'time\tload1\tload5\tcpu_idle_pct\ttop_processes\n' > "$LOAD"
( while kill -0 $$ 2>/dev/null; do
    la=$(sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1"\t"$2}')
    idle=$(top -l 1 -n 0 | awk '/CPU usage/ {gsub("%","",$7); print $7}')
    procs=$(ps -Ao pcpu=,comm= -r | head -3 | awk '{n=split($2,p,"/"); printf "%s %s%%; ", p[n], $1}')
    printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$la" "$idle" "$procs" >> "$LOAD"
    sleep 30
  done ) &

# Steps 1-2 run on the 2012 mini (kali-calibrated-builds.sh: sensitivity rows from this machine, Fisher, k-means,
# export, packing). Here: wait for each staged package, pull it, compile and assemble it.
STAGED="$WORK/staged-272"; KW="${EVAL_KALI_WORK:-edacc-272}"
mkdir -p "$STAGED"
NEW=""
for name in ${EVAL_BUILD_NAMES:-ultra-skm4 ultra-mix46 ultra-mix46-skm}; do
  if [ ! -e "$WORK/models/variants/$name/variant.json" ]; then
    status "2/5 waiting for $name from $KALI"
    until ssh "$KALI" "test -e $KW/staged/$name.variant.json"; do
      ssh "$KALI" "grep -q 'BUILD-FAILED $name' $KW/builds.log" && { echo "Kali build $name failed"; exit 1; }
      sleep 60
    done
    guard "assemble $name"; status "2/5 assembling $name"
    rsync -a "$KALI:$KW/staged/$name.Encoder.mlpackage" "$KALI:$KW/staged/$name.variant.json" "$STAGED/" \
      || { echo "cannot pull $name"; exit 1; }
    "$CPY" "$HERE/calibrated_ultra.py" assemble --name "$name" --staged "$STAGED" || { echo "assemble $name failed"; exit 1; }
  fi
  NEW="$NEW,local:$name"
done
NEW="${NEW#,}"
ENGINES="$REF,$NEW"
(cd "$REPO/Packages/EngineEval" && swift build -c release 2>&1 | tail -1)

fetch_shard() {   # $1 = shard-NNN: copy it from the 2012 mini into $S (replacing whatever was there)
  rm -rf "$S"; mkdir -p "$S"
  rsync -a "$KALI:$KALI_SHARDS/$1/" "$S/$1/" && "$PY" -c 'import sys; from edacc_eval.shards import read_manifest; read_manifest(sys.argv[1], check_audio=True)' "$S/$1"
}

if [ ! -e "$R/speedref/done" ]; then
  status "4/5 speed reference: $REF on shard 1"
  mkdir -p "$R/speedref"
  fetch_shard shard-001 || { echo "cannot fetch shard-001"; exit 1; }
  "$BIN" run --shard-dir "$S/shard-001" --results "$R/speedref/apple-shard-001.jsonl" --engines "$REF" --repeats 1 \
    --models-dir "$WORK/models" --status "$WORK/status-engine.json" && touch "$R/speedref/done"
fi

N=$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["n_shards"])' "$WORK/manifests/index.json")
for k in $(seq 1 "$N"); do
  name=$(printf 'shard-%03d' "$k")
  marker="$R/done-$name"
  [ -e "$marker" ] && continue
  guard "$name"; status "4/5 accuracy, $name of $N: $NEW"
  [ -d "$S/$name" ] || fetch_shard "$name" || { echo "cannot fetch $name"; exit 1; }
  "$BIN" run --shard-dir "$S/$name" --results "$R/apple-$name.jsonl" --engines "$NEW" --repeats 1 \
    --models-dir "$WORK/models" --status "$WORK/status-engine.json" && touch "$marker"
  if [ "$k" != 1 ]; then rm -rf "$S"; fi       # shard 1 stays for latency and memory
done

guard latency; status "5/5 live latency (shard 1) and memory"
[ -d "$S/shard-001" ] || fetch_shard shard-001 || { echo "cannot fetch shard-001"; exit 1; }
"$BIN" latency --shard-dir "$S/shard-001" --out "$R/latency/latency-shard-001.jsonl" \
  --engines "$ENGINES" --models-dir "$WORK/models" --status "$WORK/status-engine.json"
if ! grep -q '"kind":"timing"' "$R/latency/latency-shard-001.jsonl"; then
  mv "$R/latency/latency-shard-001.jsonl" "$R/latency/streams-shard-001.jsonl"
  { grep '"kind":"timing"' "$WORK/results/latency/latency-shard-001.jsonl"; cat "$R/latency/streams-shard-001.jsonl"; } \
    > "$R/latency/latency-shard-001.jsonl"
fi
IFS=',' read -ra MEMS <<< "$ENGINES"
for e in "${MEMS[@]}"; do
  "$BIN" memory --shard-dir "$S/shard-001" --engines "$e" --clips 60 --models-dir "$WORK/models" \
    --out "$R/memory/memory.jsonl" || echo "memory $e failed"
done
for e in "${MEMS[@]}"; do
  b="${e#local:}"
  m=$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["method"])' "$WORK/models/variants/$b/variant.json")
  "$PY" -m edacc_eval.cli sizes --out "$SIZES" --model "$b" --folder "$WORK/models/variants/$b" --method "$m" \
    --license "CC BY 4.0 (attribution in NOTICE.txt)"
done
MODELS="parakeet-ultra-coreml,ultra-pal6,ultra-pal4,$(echo "$NEW" | sed 's/local://g')"
# Scoring runs on the 2012 mini (owner, 2026-11-09): the same repo code, results rsynced over.
rsync -a --include='*.jsonl' --exclude='*/' --exclude='*' "$R/" "$KALI:$KW/results/r272/" \
  && rsync -a --delete --exclude='__pycache__' "$HERE/" "$KALI:$KW/code/" \
  && rsync -a "$SPLIT" "$KALI:$KW/" \
  && ssh "$KALI" bash -s <<KALI_EOF | tee "$R/heldout.txt"
cd ~/$KW/code && python3 -I -c "import sys; sys.path.insert(0, '.'); from edacc_eval.cli import main; raise SystemExit(main())" \
  heldout-report --shards ~/edacc-eval/shards --split ../edacc-heldout-split.json \
  --results ../results/r150 ../results/r272 --ref ultra-pal6 --models "$MODELS" --json-out ../heldout-272.json
KALI_EOF
rsync -a "$KALI:$KW/heldout-272.json" "$R/heldout.json" || echo "held-out report not copied back"
rm -rf "$S"
status "FINISHED"
echo "$(date '+%F %T') CALIBRATED-DONE"
