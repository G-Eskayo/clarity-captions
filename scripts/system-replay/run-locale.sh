#!/bin/sh
# #273 locale test (dev split only): what each build does when the caption language is not the language spoken.
#   scripts/system-replay/run-locale.sh CONVERSATIONS_DIR OUT_DIR   (needs at-build.sh for 3c56e56 build-1.1.0-9 and be128a5 build-1.1.0-10)
CONV="$1"; OUT="$2"; mkdir -p "$OUT"
T=~/seal-replay/trees; P=~/edacc-eval/models/release/ultra-pal6/ParakeetUltra; D=~/Developer/clarity-captions/Apps/Spike/Resources/Models/Sortformer_v2.1.mlmodelc
calm() { while [ "$(sysctl -n kern.memorystatus_vm_pressure_level)" != 1 ]; do echo "waiting on memory" >&2; sleep 60; done; }
one() { # build label dir extra...
  bin="$T/$1/Packages/SystemReplay/.build/release/system-replay"; label="$2"; dir="$3"; shift 3; dir="$OUT/$dir"; mkdir -p "$dir"
  for f in "$CONV"/*.48k.wav; do id=$(basename $f .48k.wav); [ -f "$dir/$id.json" ] && continue; calm
    "$bin" run --audio "$f" --out "$dir/$id.json" --diarizer "$D" --parakeet "$P" --path source --tail 0 --label "$label" "$@" 2>/dev/null | grep SYSTEM-REPLAY || echo "failed $dir $id"
  done
}
for loc in en-US es-ES pt-BR fr-FR nl-NL cs-CZ de-DE it-IT; do
  one build-1.1.0-9 build-1.1.0-9@3c56e56 b9-$loc --locale $loc
  one build-1.1.0-10 build-1.1.0-10@be128a5 b10-$loc --locale $loc
done
one build-1.1.0-9 build-1.1.0-9@3c56e56 b9-en-US-apple --locale en-US --engine apple
echo ALL-DONE
