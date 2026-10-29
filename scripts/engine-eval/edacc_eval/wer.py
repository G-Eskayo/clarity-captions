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
    return _align(reference.split(), hypothesis.split())


def char_counts(reference: str, hypothesis: str) -> Counts:
    """Character error counts for CER (#202): the same alignment over characters, single spaces between words
    included, so a joined or split Hebrew prefix costs one character, not a whole word. O(R*H) in characters."""
    return _align(list(" ".join(reference.split())), list(" ".join(hypothesis.split())))


# Above this many cells (R*H) the alignment runs in C through rapidfuzz, when installed: eval-d1 transcripts run to
# 3,000+ characters, 10M cells a clip, minutes each in Python. Same minimum edit distance, so WER and CER are
# identical; on a tie the split between S, D and I may differ. FLEURS clips stay on the Python path.
FAST_CELLS = 250_000


def _align(ref: list[str], hyp: list[str]) -> Counts:
    if len(ref) * len(hyp) > FAST_CELLS:
        try:
            from rapidfuzz.distance import Levenshtein
        except ImportError:
            pass
        else:
            ops = [op for op, _, _ in Levenshtein.editops(ref, hyp)]
            return Counts(sub=ops.count("replace"), dele=ops.count("delete"), ins=ops.count("insert"), n=len(ref))
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


def align_pairs(reference: list[str], hypothesis: list[str]) -> list[tuple[int | None, int | None]]:
    """Minimum-edit alignment path as (ref index or None, hyp index or None) pairs: equal/substitution pairs carry
    both, deletions carry only ref, insertions only hyp. Same tie order as align_counts. O(R*H) time and space."""
    R, H = len(reference), len(hypothesis)
    cost = [[0] * (H + 1) for _ in range(R + 1)]
    for i in range(R + 1):
        cost[i][0] = i
    for j in range(H + 1):
        cost[0][j] = j
    for i in range(1, R + 1):
        ri = reference[i - 1]
        row, prev = cost[i], cost[i - 1]
        for j in range(1, H + 1):
            if ri == hypothesis[j - 1]:
                row[j] = prev[j - 1]
            else:
                row[j] = 1 + min(prev[j - 1], prev[j], row[j - 1])
    pairs: list[tuple[int | None, int | None]] = []
    i, j = R, H
    while i > 0 or j > 0:
        if i > 0 and j > 0 and reference[i - 1] == hypothesis[j - 1] and cost[i][j] == cost[i - 1][j - 1]:
            pairs.append((i - 1, j - 1)); i -= 1; j -= 1
        elif i > 0 and j > 0 and cost[i][j] == cost[i - 1][j - 1] + 1:
            pairs.append((i - 1, j - 1)); i -= 1; j -= 1
        elif i > 0 and cost[i][j] == cost[i - 1][j] + 1:
            pairs.append((i - 1, None)); i -= 1
        else:
            pairs.append((None, j - 1)); j -= 1
    pairs.reverse()
    return pairs


def matched_reference(reference: list[str], hypothesis: list[str]) -> set[int]:
    """Reference word indices that the hypothesis gets exactly right under the minimum-edit alignment."""
    return {i for i, j in align_pairs(reference, hypothesis)
            if i is not None and j is not None and reference[i] == hypothesis[j]}
