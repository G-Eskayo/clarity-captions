"""Word error rate = (S + D + I) / N (docs/testing/test-plan.md §3), pooled, with a speaker bootstrap (#145).

Inputs are already-normalized strings; split on whitespace.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass
from typing import Iterable, Mapping


@dataclass(frozen=True)
class Counts:
    sub: int
    dele: int
    ins: int
    n: int

    @property
    def errors(self) -> int:
        return self.sub + self.dele + self.ins


def align_counts(reference: str, hypothesis: str) -> Counts:
    """Minimum-edit word alignment; ties prefer substitution, then deletion, then insertion. O(R*H) time, O(H) rows."""
    ref = reference.split()
    hyp = hypothesis.split()
    # Each cell: (cost, sub, del, ins)
    prev = [(j, 0, 0, j) for j in range(len(hyp) + 1)]
    for i in range(1, len(ref) + 1):
        cur = [(i, 0, i, 0)]
        for j in range(1, len(hyp) + 1):
            if ref[i - 1] == hyp[j - 1]:
                cur.append(prev[j - 1])
                continue
            d = prev[j - 1]
            sub = (d[0] + 1, d[1] + 1, d[2], d[3])
            u = prev[j]
            dele = (u[0] + 1, u[1], u[2] + 1, u[3])
            l = cur[j - 1]
            ins = (l[0] + 1, l[1], l[2], l[3] + 1)
            cur.append(min(sub, dele, ins, key=lambda c: c[0]))
        prev = cur
    _, s, d, ins = prev[-1]
    return Counts(sub=s, dele=d, ins=ins, n=len(ref))


def pooled_wer(counts: Iterable[Counts]) -> float:
    errors = n = 0
    for c in counts:
        errors += c.errors
        n += c.n
    return errors / n if n else math.nan


def bootstrap_ci(groups: Mapping[str, tuple[int, int]], n_boot: int = 1000, seed: int = 145,
                 alpha: float = 0.05) -> tuple[float, float]:
    """95% percentile CI of pooled WER, resampling groups (speakers) with replacement.

    groups: speaker -> (errors, reference words). O(n_boot * speakers).
    """
    items = [v for v in groups.values()]
    if not items:
        return math.nan, math.nan
    rng = random.Random(seed)
    k = len(items)
    stats = []
    for _ in range(n_boot):
        e = n = 0
        for _ in range(k):
            ge, gn = items[rng.randrange(k)]
            e += ge
            n += gn
        if n:
            stats.append(e / n)
    if not stats:
        return math.nan, math.nan
    stats.sort()
    lo = stats[int(math.floor((alpha / 2) * (len(stats) - 1)))]
    hi = stats[int(math.ceil((1 - alpha / 2) * (len(stats) - 1)))]
    return lo, hi
