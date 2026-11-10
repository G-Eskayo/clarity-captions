"""Diarization error rate, frame-based (#271).

DER = (missed + false alarm + confusion) / reference speech, overlap counted per speaker (the NIST md-eval
definition, and how NVIDIA's model card scores AMI: no collar, overlap included). Hypothesis speakers are mapped
one-to-one to reference speakers to maximise matched time; unmatched hypothesis speakers are all confusion.
10 ms frames. O(F * S) for F frames and S speakers, plus O(R * 2^H * H) for the mapping (R, H <= ~8 here).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Hashable, Iterable

FRAME = 0.01


@dataclass(frozen=True)
class DerCounts:
    ref: int        # reference speaker-frames
    miss: int
    fa: int
    conf: int

    @property
    def errors(self) -> int:
        return self.miss + self.fa + self.conf

    @property
    def der(self) -> float:
        return self.errors / self.ref if self.ref else float("nan")

    def __add__(self, o: "DerCounts") -> "DerCounts":
        return DerCounts(self.ref + o.ref, self.miss + o.miss, self.fa + o.fa, self.conf + o.conf)


ZERO = DerCounts(0, 0, 0, 0)


def _frames(t: float) -> int:
    return int(round(t / FRAME))


def _masks(segs: Iterable[tuple[Hashable, float, float]], lo: int, hi: int) -> dict[Hashable, bytearray]:
    n = hi - lo
    out: dict[Hashable, bytearray] = {}
    for spk, s, e in segs:
        a, b = max(_frames(s), lo) - lo, min(_frames(e), hi) - lo
        if b <= a:
            continue
        m = out.setdefault(spk, bytearray(n))
        m[a:b] = b"\x01" * (b - a)
    return out


def best_mapping(overlap: list[list[int]]) -> tuple[int, dict[int, int]]:
    """Max-total one-to-one assignment of rows (ref) to columns (hyp). Bitmask DP; exact."""
    R = len(overlap)
    H = len(overlap[0]) if R else 0
    memo: dict[tuple[int, int], tuple[int, tuple]] = {}

    def go(i: int, used: int) -> tuple[int, tuple]:
        if i == R:
            return 0, ()
        key = (i, used)
        if key in memo:
            return memo[key]
        best = go(i + 1, used)                       # ref i left unmatched
        best = (best[0], ((i, None),) + best[1])
        for j in range(H):
            if not used >> j & 1 and overlap[i][j] > 0:
                v, rest = go(i + 1, used | 1 << j)
                if v + overlap[i][j] > best[0]:
                    best = (v + overlap[i][j], ((i, j),) + rest)
        memo[key] = best
        return best

    total, pairs = go(0, 0)
    return total, {i: j for i, j in pairs if j is not None}


def der(ref: Iterable[tuple[Hashable, float, float]], hyp: Iterable[tuple[Hashable, float, float]],
        uem: tuple[float, float]) -> DerCounts:
    """Segments are (speaker, start, end) in seconds; only time inside `uem` is scored."""
    lo, hi = _frames(uem[0]), _frames(uem[1])
    rm, hm = _masks(ref, lo, hi), _masks(hyp, lo, hi)
    n = hi - lo
    nr, nh = [0] * n, [0] * n
    for masks, counts in ((rm, nr), (hm, nh)):
        for m in masks.values():
            for f, v in enumerate(m):
                if v:
                    counts[f] += 1
    rk, hk = list(rm), list(hm)
    rint = [int.from_bytes(rm[k], "little") for k in rk]
    hint = [int.from_bytes(hm[k], "little") for k in hk]
    overlap = [[(a & b).bit_count() for b in hint] for a in rint]
    correct, _ = best_mapping(overlap) if rk and hk else (0, {})
    miss = fa = both = 0
    for r, h in zip(nr, nh):
        if r > h:
            miss += r - h
        elif h > r:
            fa += h - r
        both += min(r, h)
    return DerCounts(ref=sum(nr), miss=miss, fa=fa, conf=both - correct)
