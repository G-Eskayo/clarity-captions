# Sourced, POSIX sh. ensure_local DIR: if this machine keeps a cold store (MARVIN's `marvin-cold`) and DIR, or the
# folder DIR sits in, was parked there to free disk, bring it back (every file checked) before the caller reads it.
# Instant when DIR is already here. No cold store on this machine means nothing to do. It fails, and the caller should
# stop, only when the data is parked and can't come back right now (cold host off, no room, bytes that don't match):
# running on a half-empty folder would be worse.
#   SEAL_COLD_ENSURE=/path/to/tool overrides where the tool is looked for (tests, other setups).
ensure_local() {
    _cold="${SEAL_COLD_ENSURE:-$(command -v marvin-cold 2>/dev/null || echo "$HOME/.agents/bin/marvin-cold")}"
    [ -x "$_cold" ] || return 0
    "$_cold" ensure "$1" --optional > /dev/null
}
