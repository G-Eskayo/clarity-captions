"""Streaming latency: how long after a word is said does it first show up correctly (#145).

Inputs per clip: the reference words, reference word times (from timing_words + reference_word_times), and the
engine's sequence of displayed-text updates [(seconds since the first audio sample, full displayed text)].
A word counts only if it is right in the final text; its latency is the time of the first update in which the
minimum-edit alignment marks it correct, minus the time the word ended. "First text" is the time of the first
non-empty update minus the end of the first reference word. Method notes: docs/perf/engine-accuracy-design.md.
"""
from __future__ import annotations

import json
import math
import statistics
from dataclasses import dataclass
from pathlib import Path

from .normalize import normalize
from .wer import align_pairs, matched_reference


@dataclass
class ClipLatency:
    word_latencies: list[float]
    first_text: float | None
    final_correct: int
    ref_words: int


def timing_words(raw: list[dict]) -> list[tuple[str, float, float]]:
    """Engine word timestamps -> normalized words with times; a raw word that normalizes to several words
    ("21" -> twenty one) splits its time evenly; fillers vanish."""
    out: list[tuple[str, float, float]] = []
    for w in raw:
        norm = normalize(w["w"]).split()
        if not norm:
            continue
        start, end = float(w["start"]), float(w["end"])
        step = (end - start) / len(norm)
        for k, word in enumerate(norm):
            out.append((word, start + k * step, start + (k + 1) * step))
    return out


def reference_word_times(ref: list[str], timing: list[tuple[str, float, float]],
                         duration: float) -> list[tuple[float, float]]:
    """Times for each reference word: aligned (equal or substituted) timing words lend their times; runs of
    unaligned reference words are spread evenly over the gap between their aligned neighbours."""
    times: list[tuple[float, float] | None] = [None] * len(ref)
    for i, j in align_pairs(ref, [w for w, _, _ in timing]):
        if i is not None and j is not None:
            times[i] = (timing[j][1], timing[j][2])
    i = 0
    while i < len(ref):
        if times[i] is not None:
            i += 1
            continue
        k = i
        while k < len(ref) and times[k] is None:
            k += 1
        lo = times[i - 1][1] if i > 0 else 0.0
        hi = times[k][0] if k < len(ref) else duration
        hi = max(hi, lo)
        step = (hi - lo) / (k - i)
        for m in range(i, k):
            times[m] = (lo + (m - i) * step, lo + (m - i + 1) * step)
        i = k
    return [t for t in times if t is not None]


def clip_latency(ref: list[str], ref_times: list[tuple[float, float]],
                 updates: list[tuple[float, str]]) -> ClipLatency:
    seq = sorted(((t, normalize(text).split()) for t, text in updates), key=lambda u: u[0])
    seq = [(t, words) for t, words in seq if words]
    if not seq:
        return ClipLatency([], None, 0, len(ref))
    final_ok = matched_reference(ref, seq[-1][1])
    first_ok: dict[int, float] = {}
    last_words = None
    for t, words in seq:
        if words == last_words:
            continue
        last_words = words
        for i in matched_reference(ref, words):
            if i in final_ok and i not in first_ok:
                first_ok[i] = t
        if len(first_ok) == len(final_ok):
            break
    lat = [first_ok[i] - ref_times[i][1] for i in sorted(first_ok)]
    first_text = seq[0][0] - ref_times[0][1] if ref_times else None
    return ClipLatency(lat, first_text, len(final_ok), len(ref))


def growing_window(duration: float, hop: float, decode) -> list[tuple[float, str]]:
    """Same as Swift's GrowingWindow.simulate: re-decode all audio so far; the next decode starts when the last one
    finished and at least `hop` s of new audio exist; a decode starting at t sees audio up to min(t, duration) and
    shows its text at t + compute. decode(audio_end) -> (text, compute_seconds). The last decode covers the clip."""
    updates: list[tuple[float, str]] = []
    t = min(hop, duration)
    while True:
        a = min(t, duration)
        text, compute = decode(a)
        shown = t + compute
        updates.append((shown, text))
        if a >= duration:
            break
        t = max(shown, min(a + hop, duration))
    return updates


def percentile(values: list[float], p: float) -> float:
    if not values:
        return math.nan
    v = sorted(values)
    pos = (len(v) - 1) * p / 100
    lo, hi = math.floor(pos), math.ceil(pos)
    return v[lo] + (v[hi] - v[lo]) * (pos - lo)


def summarize(clips: list[ClipLatency]) -> dict:
    words = [x for c in clips for x in c.word_latencies]
    firsts = [c.first_text for c in clips if c.first_text is not None]
    ref = sum(c.ref_words for c in clips)
    return {"clips": len(clips), "words": len(words), "median": percentile(words, 50), "p95": percentile(words, 95),
            "first_text_median": percentile(firsts, 50), "first_text_p95": percentile(firsts, 95),
            "final_correct_share": (sum(c.final_correct for c in clips) / ref) if ref else math.nan}


def analyze(latency_file: Path, manifest_rows: list[dict]) -> dict:
    """latency_file lines: {"kind": "timing", clip_id, words:[{w,start,end}], ...} and
    {"kind": "stream", clip_id, engine, model, method, updates:[{t, text}], ...}. Returns per-label summaries."""
    clips = {m["clip_id"]: m for m in manifest_rows}
    timing: dict[str, list[dict]] = {}
    streams: dict[tuple[str, str], dict] = {}
    for raw in Path(latency_file).read_text(encoding="utf-8").splitlines():
        try:
            row = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if not isinstance(row, dict) or row.get("clip_id") not in clips:
            continue
        if row.get("kind") == "timing":
            timing.setdefault(row["clip_id"], row["words"])
        elif row.get("kind") == "stream":
            label = f"{row['engine']} ({row['model']})"
            streams.setdefault((label, row["clip_id"]), row)
    labels = sorted({lab for lab, _ in streams})
    common = [c for c in clips if c in timing and all((lab, c) in streams for lab in labels)]
    out: dict = {"clips": len(common), "audio_seconds": sum(float(clips[c]["audio_seconds"]) for c in common),
                 "engines": {}}
    for lab in labels:
        results = []
        for c in common:
            ref = normalize(clips[c]["reference"]).split()
            times = reference_word_times(ref, timing_words(timing[c]), float(clips[c]["audio_seconds"]))
            ups = [(float(u["t"]), u["text"]) for u in streams[(lab, c)]["updates"]]
            results.append(clip_latency(ref, times, ups))
        summary = summarize(results)
        summary["method"] = streams[(lab, common[0])].get("method", "") if common else ""
        out["engines"][lab] = summary
    return out
