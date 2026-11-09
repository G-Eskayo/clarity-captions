#!/bin/sh
# The #273 first target: 1.0 (5) vs 1.1.0 (10) on the same audio, one change at a time (owner, 2026-11-09).
#
#   scripts/system-replay/run-ab.sh CONVERSATIONS_DIR SPLIT OUT_DIR
#
# Arms, run one after another (one speech model in memory at a time), each resumable:
#   A  1.0 (5), Apple's engine                     engine's own startReplaying  (the only file path 1.0 has)
#   B  1.1.0 (10), Parakeet (what it ships)         startReplaying
#   C  1.1.0 (10), Apple's engine (forced)          startReplaying   A vs C: what 1.1 changed outside the engine
#                                                                    B vs C: the engine, on the streaming path
#   D  1.1.0 (10), Parakeet, AudioSource + Start    the mic's own path: is the replay mechanism itself neutral?
# Every arm hears the same 48 kHz Float32 files, the shape of the iPhone mic's buffers.
#
# Needs: at-build.sh run for 4e7f55a (build-1.0-5) and be128a5 (build-1.1.0-10); the shipped Parakeet model
# (scripts/models/ultra-pal6.sha256) at $SEAL_PARAKEET; the speaker model at $SEAL_DIARIZER.
set -eu
CONV="$1"
SPLIT="$2"
OUT="$3"
TREES="${SEAL_REPLAY_TREES:-$HOME/seal-replay/trees}"
P="${SEAL_PARAKEET:-$HOME/edacc-eval/models/release/ultra-pal6/ParakeetUltra}"
D="${SEAL_DIARIZER:-$HOME/Developer/clarity-captions/Apps/Spike/Resources/Models/Sortformer_v2.1.mlmodelc}"
B1="$TREES/build-1.0-5/Packages/SystemReplay/.build/release/system-replay"
B10="$TREES/build-1.1.0-10/Packages/SystemReplay/.build/release/system-replay"
for b in "$B1" "$B10"; do [ -x "$b" ] || { echo "run-ab: missing $b (run at-build.sh)" >&2; exit 2; }; done
[ -d "$P" ] && [ -d "$D" ] || { echo "run-ab: model missing ($P or $D)" >&2; exit 2; }

LIST="$OUT/list.jsonl"
mkdir -p "$OUT"
python3 -I -c '
import json, sys
for l in open(sys.argv[1]):
    c = json.loads(l)
    print(json.dumps({"id": c["id"], "file": c["file"]}))
' "$CONV/conversations-$SPLIT.jsonl" > "$LIST"

# One process per session, every arm: a session that doesn't give everything back at Stop (1.0's Stop takes minutes on
# a Mac with no microphone) can't hold a speech recognizer into the next one. Resumable: a finished session is skipped.
arm() {
    bin="$1"; dir="$OUT/$2"; shift 2
    mkdir -p "$dir"
    python3 -I -c 'import json,sys; [print(json.loads(l)["id"], json.loads(l)["file"]) for l in open(sys.argv[1])]' "$LIST" |
    while read -r id file; do
        [ -f "$dir/$id.json" ] && continue
        "$bin" run --audio "$CONV/$file" --out "$dir/$id.json" "$@" 2>/dev/null | grep SYSTEM-REPLAY || echo "run-ab: $2 $id failed" >&2
    done
}
arm "$B1"  A-1.0-apple             --diarizer "$D" --path replaying --label "build-1.0-5@4e7f55a"
arm "$B10" B-10-parakeet           --diarizer "$D" --parakeet "$P" --path replaying --label "build-1.1.0-10@be128a5"
arm "$B10" C-10-apple              --diarizer "$D" --parakeet "$P" --engine apple --path replaying --label "build-1.1.0-10@be128a5"
arm "$B10" D-10-parakeet-source    --diarizer "$D" --parakeet "$P" --path source --tail 0 --label "build-1.1.0-10@be128a5"
echo "run-ab: done" >&2
