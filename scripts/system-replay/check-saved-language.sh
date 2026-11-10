#!/bin/sh
# #273 regression case: English speech with a non-English caption language saved in Seal. Run it on every build
# before it ships. It fails (exit 1) when a saved language makes English captions worse by more than 2 WER points
# with 95% confidence. Dev split only, never the scored test split.
#
#   scripts/system-replay/check-saved-language.sh NAME CONVERSATIONS_DIR OUT_DIR
#       NAME: a tree built by at-build.sh (e.g. build-1.1.0-11); CONVERSATIONS_DIR: the 8 validation
#       conversations (replay.py stitch --split validation --48k); OUT_DIR: one session log per run, resumable.
#
# On the Mac, Apple's engine has no Dutch or Czech model, so the languages are the five that have one. Build 9
# fails (+26 to +65 points); build 10 passes (lower bounds 0 or below). Each session waits for normal memory pressure.
set -eu
NAME="$1"; CONV="$2"; OUT="$3"
TREES="${SEAL_REPLAY_TREES:-$HOME/seal-replay/trees}"
P="${SEAL_PARAKEET:-$HOME/edacc-eval/models/release/ultra-pal6/ParakeetUltra}"
D="${SEAL_DIARIZER:-$HOME/Developer/clarity-captions/Apps/Spike/Resources/Models/Sortformer_v2.1.mlmodelc}"
LANGS="${SEAL_SAVED_LANGUAGES:-es-ES pt-BR fr-FR de-DE it-IT}"
BIN="$TREES/$NAME/Packages/SystemReplay/.build/release/system-replay"
[ -x "$BIN" ] || { echo "check-saved-language: missing $BIN (run at-build.sh REF $NAME)" >&2; exit 2; }
[ -d "$P" ] && [ -d "$D" ] || { echo "check-saved-language: model missing ($P or $D)" >&2; exit 2; }
calm() { while [ "$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 1)" != 1 ]; do
    echo "check-saved-language: memory pressure not normal, waiting" >&2; sleep 60; done; }
run() { # locale
    dir="$OUT/$1"; mkdir -p "$dir"
    for f in "$CONV"/*.48k.wav; do
        id=$(basename "$f" .48k.wav); [ -f "$dir/$id.json" ] && continue; calm
        "$BIN" run --audio "$f" --out "$dir/$id.json" --diarizer "$D" --parakeet "$P" --path source --tail 0 \
            --label "$NAME" --locale "$1" 2>/dev/null | grep SYSTEM-REPLAY || echo "check-saved-language: $1 $id failed" >&2
    done
}
run en-US
SAVED=""
for l in $LANGS; do run "$l"; SAVED="$SAVED --saved $l=$OUT/$l"; done
# shellcheck disable=SC2086  # word splitting on purpose
python3 -I "$(dirname "$0")/replay.py" gate-language --conversations "$CONV/conversations-validation.jsonl" \
    --english "$OUT/en-US" $SAVED --out "$OUT/gate.json"
