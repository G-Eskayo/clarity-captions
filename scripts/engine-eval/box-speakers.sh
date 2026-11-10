#!/bin/bash
# 2012 Mac mini (Kali): Android-capable speaker engines on the #276 scoreboard (#160). Same test recordings, same
# caption stream, same scorer as m4-speakers.sh; the engine runs on the CPU through ONNX Runtime instead of Core ML.
# Resumable (a result that exists is skipped); one process per recording; JOBS recordings at a time.
#   LABEL=recogment-v2|talkbar-8spk|sherpa-wespeaker SET=ami|chime6 JOBS=3 scripts/engine-eval/box-speakers.sh
# Layout (~/speaker-160): venv/, bin/py (puts code/ on sys.path for python -I), code/{speaker_onnx,speaker_eval},
# models/<name>/, ref/<set>/{rttm,uem,phrases} (phrases exist for TEST recordings only, from speaker_eval.cli phrases).
set -uo pipefail
ROOT="${ROOT:-$HOME/speaker-160}"
SET="${SET:-ami}"
LABEL="${LABEL:?LABEL is the engine: recogment-v2, talkbar-8spk or sherpa-wespeaker}"
JOBS="${JOBS:-3}"
THREADS="${THREADS:-2}"
REPEAT="${REPEAT:-1}"
case "$SET" in
  ami)    AUDIO="$HOME/ami-eval/audio" ;;
  chime6) AUDIO="$HOME/chime6-eval/windows" ;;
  *) echo "SET must be ami or chime6"; exit 2 ;;
esac
M="$ROOT/models"
case "$LABEL" in
  recogment-v2) ENGINE=(sortformer --model "$M/recogment-v2/diar_streaming_sortformer_4spk-v2.onnx") ;;
  talkbar-8spk) ENGINE=(sortformer --speakers 8 --model "$M/talkbar-8spk/diar_streaming_sortformer_8spk-v1.onnx") ;;
  sherpa-wespeaker) ENGINE=(sherpa --seg "$M/sherpa/sherpa-onnx-pyannote-segmentation-3-0/model.onnx"
                            --emb "$M/sherpa/wespeaker_en_voxceleb_resnet34.onnx") ;;
  *) echo "unknown LABEL $LABEL"; exit 2 ;;
esac
OUT="$ROOT/results/$SET"; LOGS="$ROOT/logs/$SET"
mkdir -p "$OUT" "$LOGS"

run_one() {
  rec="$1"; out="$OUT/$rec.$LABEL.r$REPEAT.json"
  [ -s "$out" ] && { echo "$rec done"; return 0; }
  nice -n 5 "$ROOT/venv/bin/python" -I "$ROOT/bin/py" speaker_onnx.run "${ENGINE[@]}" --threads "$THREADS" \
    --audio "$AUDIO/$rec.wav" --phrases "$ROOT/ref/$SET/phrases/$rec.phrases.json" --recording "$rec" \
    --label "$LABEL" --out "$out" > "$LOGS/$rec.$LABEL.r$REPEAT.log" 2>&1 \
    && tail -1 "$LOGS/$rec.$LABEL.r$REPEAT.log" || { echo "$rec FAILED (see $LOGS)"; return 1; }
}
export -f run_one; export OUT LOGS ROOT AUDIO SET LABEL THREADS REPEAT
ENGINE_STR=$(printf '%q ' "${ENGINE[@]}"); export ENGINE_STR

# Longest recordings first, so the last worker isn't left with the longest one.
ls -S "$ROOT/ref/$SET/phrases/"*.phrases.json | xargs -n1 basename | sed 's/\.phrases\.json$//' \
  | xargs -P "$JOBS" -I{} bash -c 'eval "ENGINE=($ENGINE_STR)"; run_one "$@"' _ {}
status=$?
echo "$(date '+%F %T') $LABEL $SET finished (xargs status $status)"
exit $status
