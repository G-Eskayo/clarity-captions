#!/bin/sh
# Generates the spike's Xcode project with signing already set, so opening it and pressing Run just works.
# Team ID comes from $DEVELOPMENT_TEAM or the gitignored Apps/Spike/.team (find yours in Xcode > Settings > Accounts).
# Fails if the speaker model has not been fetched yet (scripts/fetch-diarizer-models.sh).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM="${DEVELOPMENT_TEAM:-$(cat "$ROOT/Apps/Spike/.team" 2>/dev/null || true)}"
[ -n "$TEAM" ] || echo "note: no team set; you will have to pick one in Xcode's Signing & Capabilities" >&2
export DEVELOPMENT_TEAM="$TEAM"
cd "$ROOT/Apps/Spike" && xcodegen generate
