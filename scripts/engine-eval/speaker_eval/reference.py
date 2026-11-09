"""Reference speech (RTTM + UEM) and the caption stream built from it (#271).

The app shows one caption line at a time, so the replay needs a single non-overlapping stream of lines. We build it
from the reference, not from a speech engine, so the score measures the speaker path alone (engine timing is #273's
whole-system replay):

1. each speaker's segments closer than TURN_GAP are one turn (a breath is not a new line);
2. at every moment the line belongs to the speaker who started talking most recently and is still talking (someone
   who cuts in takes the line; when they stop, it goes back to whoever is still talking);
3. a stretch longer than MAX_LINE is cut into equal lines no longer than MAX_LINE (the engine ends a line eventually).

Speech by a second person underneath someone else's line has no line of its own, so the live-path DER has a floor
above zero on overlapped speech; `oracle_floor` in score.py measures it.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path

TURN_GAP = 0.5
MAX_LINE = 10.0


@dataclass(frozen=True)
class Seg:
    speaker: str
    start: float
    end: float


@dataclass(frozen=True)
class Phrase:
    start: float
    end: float
    truth: str


def read_rttm(path: Path) -> dict[str, list[Seg]]:
    """recording -> segments. Skips zero-length lines. O(lines)."""
    out: dict[str, list[Seg]] = {}
    for line in Path(path).read_text().splitlines():
        f = line.split()
        if len(f) < 8 or f[0] != "SPEAKER":
            continue
        start, dur = float(f[3]), float(f[4])
        if dur <= 0:
            continue
        out.setdefault(f[1], []).append(Seg(f[7], start, start + dur))
    for segs in out.values():
        segs.sort(key=lambda s: (s.start, s.end, s.speaker))
    return out


def read_uem(path: Path) -> dict[str, tuple[float, float]]:
    out = {}
    for line in Path(path).read_text().splitlines():
        f = line.split()
        if len(f) >= 4:
            out[f[0]] = (float(f[2]), float(f[3]))
    return out


def clip(segs: list[Seg], uem: tuple[float, float] | None) -> list[Seg]:
    if uem is None:
        return list(segs)
    lo, hi = uem
    return [Seg(s.speaker, max(s.start, lo), min(s.end, hi)) for s in segs if min(s.end, hi) > max(s.start, lo)]


def turns(segs: list[Seg], gap: float = TURN_GAP) -> list[Seg]:
    """Each speaker's segments merged across pauses shorter than `gap`. O(n log n)."""
    by: dict[str, list[Seg]] = {}
    for s in sorted(segs, key=lambda s: s.start):
        cur = by.setdefault(s.speaker, [])
        if cur and s.start - cur[-1].end < gap:
            cur[-1] = Seg(s.speaker, cur[-1].start, max(cur[-1].end, s.end))
        else:
            cur.append(s)
    return sorted((t for ts in by.values() for t in ts), key=lambda s: (s.start, s.speaker))


def phrases(segs: list[Seg], gap: float = TURN_GAP, max_line: float = MAX_LINE) -> list[Phrase]:
    """The caption stream: non-overlapping lines in time order, each owned by one reference speaker.

    O(T^2) in the worst case for T turns active at once (T is at most the speaker count, so effectively O(T log T)).
    """
    ts = turns(segs, gap)
    points = sorted({t.start for t in ts} | {t.end for t in ts})
    runs: list[list] = []      # [speaker, start, end]
    i = 0
    active: list[Seg] = []
    for a, b in zip(points, points[1:]):
        while i < len(ts) and ts[i].start <= a:
            active.append(ts[i]); i += 1
        active = [t for t in active if t.end > a]
        if not active:
            continue
        holder = max(active, key=lambda t: (t.start, t.speaker)).speaker
        if runs and runs[-1][0] == holder and math.isclose(runs[-1][2], a):
            runs[-1][2] = b
        else:
            runs.append([holder, a, b])
    out: list[Phrase] = []
    for spk, s, e in runs:
        n = max(1, math.ceil((e - s) / max_line - 1e-9))
        step = (e - s) / n
        for k in range(n):
            out.append(Phrase(s + k * step, s + (k + 1) * step if k < n - 1 else e, spk))
    return out


def long_monologues(segs: list[Seg], min_span: float = 20.0, gap: float = 2.0) -> list[Seg]:
    """One voice talking a long time (the #91 split case): a speaker's own speech joined across pauses under `gap`,
    spanning at least `min_span` seconds. Others' backchannels underneath don't break it."""
    return [t for t in turns(segs, gap) if t.end - t.start >= min_span]
