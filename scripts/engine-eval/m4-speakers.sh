#!/bin/bash
# M4 Mac mini: the real-voice speaker scoreboard (#271). Test audio lives on the 2012 mini; each recording is copied
# here, run through the app's live speaker path once per repeat (one process per run, so peak memory is per
# recording), then deleted. Resumable: a run whose result file exists is skipped.
#   EVAL_REPO=<worktree> MODEL=<dir.mlmodelc> LABEL=fp16 SET=ami|chime6 scripts/engine-eval/m4-speakers.sh
# Calibration recordings are never run here: the list comes from `speaker_eval.cli phrases`, which writes test only.
#   ami:    2012 mini ami-eval/audio/<meeting>.wav; reference from ami-eval/setup (pyannote AMI-diarization-setup)
#   chime6: 2012 mini chime6-eval/windows/<window>.wav (chime6-cut.py); reference from speaker_eval.chime6
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

REMOTE="${EVAL_REMOTE:-mac-mini-2012}"
SET="${SET:-ami}"
REPO="${EVAL_REPO:?EVAL_REPO must point at the clarity-captions worktree}"
MODEL="${MODEL:?MODEL must point at the .mlmodelc to score}"
LABEL="${LABEL:-fp16}"
REPEATS="${EVAL_REPEATS:-2}"
PY="${EVAL_PY:-$HOME/.agents/venv/bin/python}"
BIN="$REPO/Packages/EngineEval/.build/release/engine-eval"
case "$SET" in
  ami)    WORK="${EVAL_WORK:-$HOME/ami-eval}"; AUDIO="ami-eval/audio" ;;
  chime6) WORK="${EVAL_WORK:-$HOME/chime6-eval}"; AUDIO="chime6-eval/windows" ;;
  *) echo "SET must be ami or chime6"; exit 2 ;;
esac
mkdir -p "$WORK"/{audio,results,phrases,report,logs,rttm,uem}

[ -x "$BIN" ] || (cd "$REPO/Packages/EngineEval" && swift build -c release --product engine-eval) || { echo "build failed"; exit 1; }
if [ "$SET" = ami ]; then
  rsync -a "$REMOTE:ami-eval/setup/only_words/rttms/test/" "$WORK/rttm/" && rsync -a "$REMOTE:ami-eval/setup/uems/test/" "$WORK/uem/" \
    || { echo "cannot fetch the reference from $REMOTE"; exit 1; }
else
  rsync -a "$REMOTE:chime6-eval/ref/CHiME6_transcriptions/transcriptions/transcriptions/" "$WORK/transcripts/" \
    || { echo "cannot fetch the transcripts from $REMOTE"; exit 1; }
  (cd "$REPO/scripts/engine-eval" && "$PY" -c "from pathlib import Path; from speaker_eval.chime6 import write_reference; \
write_reference(Path('$WORK/transcripts'), ['S01', 'S21', 'S02', 'S09'], Path('$WORK'))") || { echo "chime6 reference failed"; exit 1; }
fi
(cd "$REPO/scripts/engine-eval" && "$PY" -m speaker_eval.cli phrases --set "$SET" --rttm-dir "$WORK/rttm" \
  --uem-dir "$WORK/uem" --out "$WORK/phrases") > "$WORK/logs/phrases.log" || { echo "phrases failed"; exit 1; }

errors=0
for ph in "$WORK"/phrases/*.phrases.json; do
  rec=$(basename "$ph" .phrases.json)
  need=0
  for r in $(seq 1 "$REPEATS"); do [ -s "$WORK/results/$rec.$LABEL.r$r.json" ] || need=1; done
  [ "$need" -eq 1 ] || { echo "$rec done"; continue; }
  rsync -a "$REMOTE:$AUDIO/$rec.wav" "$WORK/audio/" || { echo "$rec: fetch failed"; errors=$((errors+1)); continue; }
  for r in $(seq 1 "$REPEATS"); do
    out="$WORK/results/$rec.$LABEL.r$r.json"
    [ -s "$out" ] && continue
    "$BIN" speakers --audio "$WORK/audio/$rec.wav" --phrases "$ph" --model "$MODEL" --model-label "$LABEL" \
      --recording "$rec" --out "$out" || { echo "$rec r$r failed"; errors=$((errors+1)); }
  done
  rm -f "$WORK/audio/$rec.wav"
done
echo "$(date '+%F %T') driver finished, $errors error(s)"
exit $(( errors > 0 ))
