"""chrF and COMET scores with group-bootstrap confidence intervals, and speed per caption line (#159).

chrF bootstrap resamples groups (FLORES articles, WMT documents) and recomputes a real corpus chrF from summed
sufficient statistics, as #145's WER bootstrap resamples speakers. Uses sacrebleu's CHRF statistics (pinned 2.x).
"""
from __future__ import annotations

import math
import random
from collections import defaultdict
from typing import Sequence

from sacrebleu.metrics import CHRF

N_BOOT = 1000
SEED = 159
_CHRF = CHRF()


def segment_stats(hypothesis: str, reference: str) -> list[int]:
    return list(_CHRF._extract_corpus_statistics([hypothesis], [[reference]])[0])


def corpus_chrf(stats: Sequence[Sequence[int]]) -> float:
    if not stats:
        return math.nan
    total = [sum(col) for col in zip(*stats)]
    return float(_CHRF._compute_score_from_stats(total).score)


def _grouped(values: Sequence, groups: Sequence[str]) -> list[list]:
    if len(values) != len(groups):
        raise ValueError(f"{len(values)} values but {len(groups)} groups")
    by: dict[str, list] = defaultdict(list)
    for v, g in zip(values, groups):
        by[g].append(v)
    return [by[g] for g in sorted(by)]


def _sum_stats(stats: Sequence[Sequence[int]]) -> list[int]:
    return [sum(col) for col in zip(*stats)]


def _percentile_ci(samples: list[float], alpha: float = 0.05) -> tuple[float, float]:
    samples = sorted(samples)
    lo = samples[int(math.floor((alpha / 2) * (len(samples) - 1)))]
    hi = samples[int(math.ceil((1 - alpha / 2) * (len(samples) - 1)))]
    return lo, hi


def chrf_bootstrap(stats: Sequence[Sequence[int]], groups: Sequence[str], n_boot: int = N_BOOT,
                   seed: int = SEED) -> tuple[float, float, float]:
    """(corpus chrF, 95% low, 95% high). O(n_boot * groups) after one O(segments) pass."""
    per_group = [_sum_stats(g) for g in _grouped(stats, groups)]
    point = corpus_chrf(stats)
    rng = random.Random(seed)
    k = len(per_group)
    samples = [corpus_chrf([per_group[rng.randrange(k)] for _ in range(k)]) for _ in range(n_boot)]
    lo, hi = _percentile_ci(samples)
    return point, lo, hi


def paired_chrf_diff(stats_a: Sequence[Sequence[int]], stats_b: Sequence[Sequence[int]], groups: Sequence[str],
                     n_boot: int = N_BOOT, seed: int = SEED) -> tuple[float, float, float]:
    """chrF(a) - chrF(b) on the same segments, with a 95% interval from shared resamples."""
    if len(stats_a) != len(stats_b):
        raise ValueError("paired systems must cover the same segments")
    ga = [_sum_stats(g) for g in _grouped(stats_a, groups)]
    gb = [_sum_stats(g) for g in _grouped(stats_b, groups)]
    point = corpus_chrf(stats_a) - corpus_chrf(stats_b)
    rng = random.Random(seed)
    k = len(ga)
    samples = []
    for _ in range(n_boot):
        idx = [rng.randrange(k) for _ in range(k)]
        samples.append(corpus_chrf([ga[i] for i in idx]) - corpus_chrf([gb[i] for i in idx]))
    lo, hi = _percentile_ci(samples)
    return point, lo, hi


def bootstrap_mean(values: Sequence[float], groups: Sequence[str], n_boot: int = N_BOOT,
                   seed: int = SEED) -> tuple[float, float, float]:
    """Mean of segment values (COMET) with a group bootstrap: resampled groups' totals / their counts."""
    if not values:
        return math.nan, math.nan, math.nan
    per_group = [(sum(g), len(g)) for g in _grouped(values, groups)]
    rng = random.Random(seed)
    k = len(per_group)
    samples = []
    for _ in range(n_boot):
        s = n = 0
        for _ in range(k):
            gs, gn = per_group[rng.randrange(k)]
            s += gs
            n += gn
        samples.append(s / n)
    lo, hi = _percentile_ci(samples)
    return sum(values) / len(values), lo, hi


def speed_summary(seconds: Sequence[float], warmup: int = 5) -> dict | None:
    """Median and p95 milliseconds per line after dropping the first `warmup` lines (model warm-up)."""
    xs = sorted(seconds[warmup:])
    if len(xs) < 3:
        return None
    def q(p: float) -> float:
        return xs[min(len(xs) - 1, int(math.ceil(p * len(xs))) - 1)] * 1000
    return {"n": len(xs), "median_ms": q(0.5), "p95_ms": q(0.95), "mean_ms": 1000 * sum(xs) / len(xs)}
