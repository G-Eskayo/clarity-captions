#!/bin/bash
# Build the harness, boot an arm64 emulator, run one pair, pull results (#159). Usage: run.sh en-es [repeats]
# Needs JAVA_HOME (JDK 21) and ANDROID_HOME with platform-tools, emulator, platforms;android-35, build-tools and
# system-images;android-35;google_apis;arm64-v8a and cmdline-tools;latest. Resumable: a rerun continues from the app's result file.
set -euo pipefail
PAIR="$1"; REPEATS="${2:-2}"; TARGET="${PAIR#en-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PKG=com.gileskayo.eval.mlkit
AVD=mlkit-eval-159
ADB="$ANDROID_HOME/platform-tools/adb"
OUT="${EVAL_OUT:-$HOME/translation-eval/results/$PAIR}"
SETS="${EVAL_SETS:-$HOME/translation-eval/sets/$PAIR}"   # the isolated timing pass points this at caption lines only
TAG="${EVAL_TAG:-$PAIR}"
echo "sdk.dir=$ANDROID_HOME" > "$HERE/local.properties"
(cd "$HERE" && gradle -q assembleRelease)
APK="$HERE/app/build/outputs/apk/release/app-release.apk"
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
if ! "$AVDMANAGER" list avd 2>/dev/null | grep -q "$AVD"; then
  echo no | "$AVDMANAGER" create avd -n "$AVD" -k "system-images;android-35;google_apis;arm64-v8a" -d pixel_7 >/dev/null
  # A 30 MB language model doesn't need the default 12 GB data partition
  sed -i '' 's/^disk.dataPartition.size=.*/disk.dataPartition.size=2G/' "${ANDROID_AVD_HOME:-$HOME/.android/avd}/$AVD.avd/config.ini"
fi
if ! "$ADB" devices | grep -q "emulator-"; then
  nohup "$ANDROID_HOME/emulator/emulator" -avd "$AVD" -no-window -no-audio -no-boot-anim -no-snapshot \
    -partition-size 2048 > "$HOME/translation-eval/logs/emulator.log" 2>&1 &
  EMU=$!
fi
until "$ADB" devices | grep -q "emulator-.*device$"; do
  if [ -n "${EMU:-}" ] && ! kill -0 "$EMU" 2>/dev/null; then echo "emulator exited:"; tail -3 "$HOME/translation-eval/logs/emulator.log"; exit 1; fi
  sleep 5
done
until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 5; done
"$ADB" install -r "$APK" >/dev/null
"$ADB" shell am force-stop "$PKG"
AS() { "$ADB" shell run-as "$PKG" "$@"; }
AS rm -f files/done.json
AS mkdir -p files/sets
AS sh -c "'rm -f files/sets/*.jsonl'"
# A different pair's results must not be resumed into this one
if [ "$(AS cat files/pair.txt 2>/dev/null | tr -d '\r')" != "$TAG" ]; then AS rm -f files/results/mlkit.jsonl; fi
echo "$TAG" | "$ADB" shell run-as "$PKG" sh -c "'cat > files/pair.txt'"
for f in "$SETS/"*.jsonl; do
  "$ADB" shell run-as "$PKG" sh -c "'cat > files/sets/$(basename "$f")'" < "$f"
done
"$ADB" shell am start -n "$PKG/.MainActivity" --es target "$TARGET" --ei repeats "$REPEATS" >/dev/null
mkdir -p "$OUT"
until AS test -f files/done.json; do
  sleep 30
  AS cat files/results/mlkit.jsonl > "$OUT/mlkit.jsonl.part" 2>/dev/null && mv "$OUT/mlkit.jsonl.part" "$OUT/mlkit.jsonl"
done
AS cat files/results/mlkit.jsonl > "$OUT/mlkit.jsonl"
AS cat files/done.json > "$OUT/mlkit-done.json"
# Size on the device of the language folder ML Kit downloaded (measured in place; the files are not copied off)
AS du -sk "no_backup/com.google.mlkit.translate.models/en_$TARGET" > "$OUT/mlkit-model-du.txt"
cat "$OUT/mlkit-done.json"; echo
