#!/bin/sh
# Builds the whole-system replay harness (Packages/SystemReplay) against the app code of another build (#273), so one
# harness replays 1.0 (5), 1.1.0 (9), 1.1.0 (10) and main on the same audio.
#
#   scripts/system-replay/at-build.sh REF NAME     e.g.  at-build.sh 4e7f55a build-1.0-5
#
# - Checks REF out as a detached worktree at $SEAL_REPLAY_TREES/NAME (default ~/seal-replay/trees/NAME). Remove it
#   afterwards with `git worktree remove` (never `git worktree prune` in this shared repo).
# - Copies this checkout's Packages/SystemReplay into it, pinned to the FluidAudio that build's CaptionCore resolved
#   (its Package.resolved), so the replay runs the speech and speaker code that build shipped.
# - Builds with -DCAPTIONCORE_1_0 when that CaptionCore has no AudioSource (1.0: Apple's engine, mic wired in).
# - Release configuration, as the app ships. Prints the binary's path last.
#
# Which commit is which build: docs/perf/whole-system-replay-design.md, "Builds".
set -eu
REF="$1"
NAME="$2"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TREES="${SEAL_REPLAY_TREES:-$HOME/seal-replay/trees}"
DEST="$TREES/$NAME"
mkdir -p "$TREES"
if [ ! -d "$DEST" ]; then
    git -C "$ROOT" worktree add --detach "$DEST" "$REF" >&2
fi
have="$(git -C "$DEST" rev-parse HEAD)"
want="$(git -C "$ROOT" rev-parse "$REF^{commit}")"
[ "$have" = "$want" ] || { echo "at-build: $DEST is at $have, not $REF ($want)" >&2; exit 2; }

rm -rf "$DEST/Packages/SystemReplay"
mkdir -p "$DEST/Packages/SystemReplay"
(cd "$ROOT/Packages/SystemReplay" && tar cf - --exclude .build --exclude Package.resolved .) | (cd "$DEST/Packages/SystemReplay" && tar xf -)

PIN="$(python3 -I - "$DEST/Packages/CaptionCore/Package.resolved" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
pins = d.get("pins") or d["object"]["pins"]
for p in pins:
    if (p.get("identity") or p.get("package", "")).lower() == "fluidaudio":
        print(p["state"]["version"])
        break
else:
    sys.exit("no FluidAudio pin")
PY
)"
sed -i '' "s|FluidAudio.git\", exact: \"[0-9.]*\"|FluidAudio.git\", exact: \"$PIN\"|" "$DEST/Packages/SystemReplay/Package.swift"
grep -q "exact: \"$PIN\"" "$DEST/Packages/SystemReplay/Package.swift" || { echo "at-build: could not pin FluidAudio $PIN" >&2; exit 2; }

FLAGS=""
if ! grep -q "protocol AudioSource" "$DEST"/Packages/CaptionCore/Sources/CaptionCore/*.swift; then
    FLAGS="-Xswiftc -DCAPTIONCORE_1_0"
fi
echo "at-build: $NAME = $want, FluidAudio $PIN, flags '${FLAGS:-none}'" >&2
# shellcheck disable=SC2086
swift build -c release --package-path "$DEST/Packages/SystemReplay" $FLAGS >&2
echo "$DEST/Packages/SystemReplay/.build/release/system-replay"
