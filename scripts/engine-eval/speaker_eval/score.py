"""Scores `engine-eval speakers` results against the reference (#271).

Per test recording: DER on what the screen shows (the live path: SpeakerLabelSmoother's final label for every line),
on the plain-overlap slot (SpeakerAligner), on the bare model's own segments, and the floor the one-line-at-a-time
screen can reach (every line given its true speaker). Plus speaker-count error, how often one long monologue is split
across two labels (#91), time to a line's first label, and speed and memory. 95% CIs: percentile bootstrap over
recordings (1,000 resamples, seed 271), the same method as #145/#150 with the meeting as the resampled unit.
"""
from __future__ import annotations

import json
import random
import statistics
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Sequence

from .der import ZERO, DerCounts, der
from .reference import Phrase, Seg, long_monologues

N_BOOT = 1000
SEED = 271


@dataclass
class RecScore:
    recording: str
    live: DerCounts
    raw: DerCounts
    bare: DerCounts
    floor: DerCounts
    ref_speakers: int
    shown_speakers: int
    bare_speakers: int
    monologues: list[tuple[bool, float]]          # (split across labels, share of labelled time on its main label)
    first_label_s: float | None                   # session: first labelled line minus first speech
    line_delays: list[float]                      # per line: first label minus line start
    unlabeled_lines: int
    lines: int
    audio_s: float
    wall_s: float
    chunk_p95_ms: float
    chunk_max_ms: float
    chunk_audio_ms: float
    peak_mb: float
    load_s: float
    extra: dict = field(default_factory=dict)


def final_labels(result: dict, key: str = "label") -> dict[int, int | None]:
    """phrase -> its final label (the settled one the transcript keeps)."""
    out: dict[int, int | None] = {}
    for e in result["emissions"]:
        if e["final"]:
            out[e["phrase"]] = e.get(key)
    return out


def score_recording(result: dict, ref: list[Seg], phrases: list[Phrase], uem: tuple[float, float]) -> RecScore:
    if result.get("phrases") != len(phrases):
        raise ValueError(f"{result['recording']}: result has {result.get('phrases')} lines, reference builds {len(phrases)}")
    refs = [(s.speaker, s.start, s.end) for s in ref]
    shown, raw = final_labels(result), final_labels(result, "raw")

    def hyp(labels):
        return [(labels[i], p.start, p.end) for i, p in enumerate(phrases) if labels.get(i) is not None]

    bare = [(s["speaker"], s["start"], s["end"]) for s in result["segments"]]
    floor = [(p.truth, p.start, p.end) for p in phrases]

    monos = []
    for m in long_monologues(ref):
        labs = Counter()
        for i, p in enumerate(phrases):
            if p.truth == m.speaker and p.start >= m.start - 1e-6 and p.end <= m.end + 1e-6 and shown.get(i) is not None:
                labs[shown[i]] += p.end - p.start
        if labs:
            monos.append((len(labs) >= 2, max(labs.values()) / sum(labs.values())))

    first: dict[int, float] = {}
    for e in result["emissions"]:
        if e.get("label") is not None and e["phrase"] not in first:
            first[e["phrase"]] = e["now"]
    delays = [first[i] - p.start for i, p in enumerate(phrases) if i in first]
    session_first = (min(first.values()) - phrases[0].start) if first and phrases else None

    cm = result.get("chunk_ms", {})
    fp = result.get("footprint_mb", {})
    return RecScore(
        recording=result["recording"], live=der(refs, hyp(shown), uem), raw=der(refs, hyp(raw), uem),
        bare=der(refs, bare, uem), floor=der(refs, floor, uem),
        ref_speakers=len({s.speaker for s in ref}),
        shown_speakers=len({v for v in shown.values() if v is not None}),
        bare_speakers=len({s["speaker"] for s in result["segments"]}),
        monologues=monos, first_label_s=session_first, line_delays=delays,
        unlabeled_lines=sum(1 for i in range(len(phrases)) if shown.get(i) is None), lines=len(phrases),
        audio_s=result["audio_seconds"], wall_s=result["wall_seconds"], chunk_p95_ms=cm.get("p95", float("nan")),
        chunk_max_ms=cm.get("max", float("nan")), chunk_audio_ms=result.get("chunk_audio_ms", 85.3),
        peak_mb=max(fp.get("peak", 0.0), fp.get("lifetime_peak", 0.0)), load_s=result["load_seconds"])


# ---- aggregation -------------------------------------------------------------------------------------------------

def pooled(recs: Sequence[RecScore], attr: str) -> float:
    total = ZERO
    for r in recs:
        total = total + getattr(r, attr)
    return total.der


def split_rate(recs: Sequence[RecScore]) -> float:
    ms = [m for r in recs for m in r.monologues]
    return sum(1 for s, _ in ms if s) / len(ms) if ms else float("nan")


def count_mae(recs: Sequence[RecScore]) -> float:
    return statistics.fmean(abs(r.shown_speakers - r.ref_speakers) for r in recs) if recs else float("nan")


def _quantile(xs: list[float], q: float) -> float:
    if not xs:
        return float("nan")
    s = sorted(xs)
    return s[min(len(s) - 1, int(round(q * (len(s) - 1))))]


def line_delay(q: float) -> Callable[[Sequence[RecScore]], float]:
    return lambda recs: _quantile([d for r in recs for d in r.line_delays], q)


def bootstrap(recs: Sequence[RecScore], stat: Callable[[Sequence[RecScore]], float], n: int = N_BOOT,
              seed: int = SEED, alpha: float = 0.05) -> tuple[float, float]:
    """Percentile CI, resampling recordings with replacement. O(n * cost(stat))."""
    if not recs:
        return float("nan"), float("nan")
    rng = random.Random(seed)
    k = len(recs)
    vals = []
    for _ in range(n):
        v = stat([recs[rng.randrange(k)] for _ in range(k)])
        if v == v:  # drop NaN (a resample with no monologues, say)
            vals.append(v)
    if not vals:
        return float("nan"), float("nan")
    vals.sort()
    return _quantile(vals, alpha / 2), _quantile(vals, 1 - alpha / 2)


def summary(recs: Sequence[RecScore]) -> dict:
    def ci(stat):
        v = stat(recs)
        lo, hi = bootstrap(recs, stat)
        return {"value": v, "ci95": [lo, hi]}

    total_live = ZERO
    for r in recs:
        total_live = total_live + r.live
    monos = [m for r in recs for m in r.monologues]
    firsts = [r.first_label_s for r in recs if r.first_label_s is not None]
    return {
        "recordings": len(recs), "audio_hours": sum(r.audio_s for r in recs) / 3600,
        "der_live": ci(lambda x: pooled(x, "live")), "der_raw": ci(lambda x: pooled(x, "raw")),
        "der_bare": ci(lambda x: pooled(x, "bare")), "der_floor": ci(lambda x: pooled(x, "floor")),
        "live_components": {"miss": total_live.miss / total_live.ref, "fa": total_live.fa / total_live.ref,
                            "conf": total_live.conf / total_live.ref} if total_live.ref else {},
        "speaker_count_mae": ci(count_mae),
        "speaker_count_exact": sum(1 for r in recs if r.shown_speakers == r.ref_speakers),
        "monologues": len(monos), "monologue_split_rate": ci(split_rate),
        "monologue_main_share_median": _quantile([s for _, s in monos], 0.5),
        "line_first_label_median_s": ci(line_delay(0.5)), "line_first_label_p90_s": ci(line_delay(0.9)),
        "unlabeled_line_rate": sum(r.unlabeled_lines for r in recs) / max(1, sum(r.lines for r in recs)),
        "session_first_label_s": {"median": _quantile(firsts, 0.5), "max": max(firsts) if firsts else float("nan")},
        "speed_x_realtime": sum(r.audio_s for r in recs) / max(1e-9, sum(r.wall_s for r in recs)),
        "chunk_ms_p95_worst": max(r.chunk_p95_ms for r in recs), "chunk_ms_max": max(r.chunk_max_ms for r in recs),
        "chunk_audio_ms": recs[0].chunk_audio_ms if recs else None,
        "peak_mb": {"median": _quantile([r.peak_mb for r in recs], 0.5), "max": max(r.peak_mb for r in recs)},
        "load_s_median": _quantile([r.load_s for r in recs], 0.5),
    }


def load_result(path: Path) -> dict:
    return json.loads(Path(path).read_text())


def same_output(a: dict, b: dict) -> bool:
    """Two runs of one recording gave identical labels and segments (the determinism check)."""
    return a["emissions"] == b["emissions"] and a["segments"] == b["segments"]
