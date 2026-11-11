"""The app's live speaker path, ported from CaptionCore for engines that don't run under Core ML (#160).

- `LabelSmoother`  = SpeakerLabelSmoother.swift (#91): what the screen shows.
- `aligner_speaker` = SpeakerAligner.swift: the plain-overlap slot (face to face).
- `replay`          = SpeakerPathReplay.swift (#271): the app's 85 ms buffers, a live result for the line being spoken
                      every 0.5 s, its final 1.0 s after it ends, silence fed after the audio until every line is final.

One difference, on purpose: Swift breaks an exact overlap tie with random dictionary order (#275). Here the lower
slot wins (unless the current speaker is tied, as in Swift). #276 measured that tie at 0.01 points of DER.
"""
from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Iterable, Iterator, Protocol, Sequence

import numpy as np

APP_CHUNK = 1365          # 4096 frames at 48 kHz, as 16 kHz samples (about 85 ms)
SAMPLE_RATE = 16000


@dataclass(frozen=True)
class Seg:
    speaker: int
    start: float
    end: float


def _overlap(start: float, end: float, s: Seg) -> float:
    return min(end, s.end) - max(start, s.start)


def _best(overlap: dict[int, float], current: int | None) -> tuple[int, float] | None:
    """Swift `max(by: a.value < b.value || (equal && b.key == current))`, with ties otherwise to the lower slot."""
    if not overlap:
        return None
    top = max(overlap.values())
    tied = sorted(k for k, v in overlap.items() if v == top)
    k = current if current in tied else tied[0]
    return k, top


def aligner_speaker(start: float, end: float, segments: Sequence[Seg]) -> int | None:
    overlap: dict[int, float] = {}
    for s in segments:
        o = _overlap(start, end, s)
        if o > 0:
            overlap[s.speaker] = overlap.get(s.speaker, 0.0) + o
    best = _best(overlap, None)
    if best:
        return best[0]
    if end <= start:
        for s in reversed(segments):
            if s.start <= start < s.end:
                return s.speaker
    return None


class LabelSmoother:
    def __init__(self, min_segment_seconds: float = 0.5, switch_seconds: float = 1.0):
        self.min_segment_seconds = min_segment_seconds
        self.switch_seconds = switch_seconds
        self.current: int | None = None
        self.current_start: float | None = None
        self.display_by_slot: dict[int, int] = {}

    def label(self, start: float, end: float, segments: Sequence[Seg], is_final: bool) -> int | None:
        slot = self._choose(start, end, segments, is_final)
        if slot is None:
            return None
        self.current, self.current_start = slot, start
        if slot not in self.display_by_slot:
            self.display_by_slot[slot] = len(self.display_by_slot)
        return self.display_by_slot[slot]

    def _choose(self, start, end, segments, is_final):
        covering = [s for s in segments if _overlap(start, end, s) > 0]
        if not covering:
            if end > start:
                return None
            for s in reversed(segments):
                if s.start <= start < s.end:
                    return s.speaker
            return None
        long = [s for s in covering if s.end - s.start >= self.min_segment_seconds]
        evidence = long or covering
        overlap: dict[int, float] = {}
        for s in evidence:
            overlap[s.speaker] = overlap.get(s.speaker, 0.0) + _overlap(start, end, s)
        best = _best(overlap, self.current)
        if best is None:
            return self.current
        key, value = best
        if not long and not is_final and key not in self.display_by_slot:
            return None
        if self.current is None or key == self.current:
            return key
        same = self.current_start is not None and abs(self.current_start - start) < 0.05
        if not is_final and same and value < self.switch_seconds:
            return self.current
        return key


class Diarizer(Protocol):
    def feed(self, samples: np.ndarray) -> None: ...
    @property
    def segments(self) -> list[Seg]: ...
    def finish(self) -> None: ...


def is_stream(phrases: Sequence[tuple[float, float]]) -> bool:
    if not all(e > s and s >= 0 for s, e in phrases):
        return False
    return all(b[0] >= a[1] for a, b in zip(phrases, phrases[1:]))


def _quantiles(ms: list[float]) -> dict:
    if not ms:
        return {}
    a = np.asarray(ms)
    return {"mean": float(a.mean()), "p50": float(np.percentile(a, 50)), "p95": float(np.percentile(a, 95)),
            "p99": float(np.percentile(a, 99)), "max": float(a.max())}


def replay(d: Diarizer, chunks: Iterable[np.ndarray], phrases: Sequence[tuple[float, float]],
           volatile_every: float = 0.5, final_delay: float = 1.0, load_seconds: float = 0.0,
           on_chunk=None) -> dict:
    """SpeakerPathReplay.run, step for step. `chunks` yields 16 kHz mono float32 audio of any length."""
    if not is_stream(phrases):
        raise ValueError("phrases must be non-empty ranges, in time order, never overlapping")
    t0 = time.monotonic()
    smoother = LabelSmoother()
    emissions: list[dict] = []
    chunk_ms: list[float] = []
    finalized: set[int] = set()
    st = {"next_final": 0, "next_volatile": volatile_every, "fed": 0}

    def ask(p: int, is_final: bool, now: float) -> None:
        start, pend = phrases[p]
        end = pend if is_final else min(now, pend)
        if not end > start:
            return
        segs = d.segments
        label = smoother.label(start, end, segs, is_final)
        raw = aligner_speaker(start, end, segs)
        emissions.append({"now": now, "phrase": p, "final": is_final, "label": label, "raw": raw})

    def step(chunk: np.ndarray) -> None:
        c0 = time.perf_counter_ns()
        d.feed(chunk)
        chunk_ms.append((time.perf_counter_ns() - c0) / 1e6)
        st["fed"] += len(chunk)
        now = st["fed"] / SAMPLE_RATE
        while st["next_final"] < len(phrases) and now >= phrases[st["next_final"]][1] + final_delay:
            finalized.add(st["next_final"]); ask(st["next_final"], True, now); st["next_final"] += 1
        if now >= st["next_volatile"]:
            st["next_volatile"] += volatile_every
            p = next((i for i in range(len(phrases) - 1, -1, -1)
                      if phrases[i][0] < now < phrases[i][1] + final_delay), None)
            if p is not None and p not in finalized:
                ask(p, False, now)
        if on_chunk:
            on_chunk(now)

    pending = np.zeros(0, np.float32)
    for more in chunks:
        pending = np.concatenate([pending, np.asarray(more, np.float32)])
        i = 0
        while len(pending) - i >= APP_CHUNK:
            step(pending[i:i + APP_CHUNK]); i += APP_CHUNK
        pending = pending[i:]
    if len(pending):
        step(pending)
    audio_seconds = st["fed"] / SAMPLE_RATE
    tail = np.zeros(APP_CHUNK, np.float32)
    while st["next_final"] < len(phrases):
        step(tail)
    d.finish()
    return {"emissions": emissions,
            "segments": [{"speaker": s.speaker, "start": s.start, "end": s.end} for s in d.segments],
            "audio_seconds": audio_seconds, "load_seconds": load_seconds,
            "wall_seconds": time.monotonic() - t0 + load_seconds,
            "chunk_ms": _quantiles(chunk_ms), "chunk_audio_ms": APP_CHUNK / SAMPLE_RATE * 1000,
            "phrases": len(phrases)}


def wav_chunks(path: str, block: int = 16000 * 10) -> Iterator[np.ndarray]:
    """16 kHz mono audio a block at a time (never the whole recording in memory)."""
    import soundfile as sf
    with sf.SoundFile(path) as f:
        if f.samplerate != SAMPLE_RATE or f.channels != 1:
            raise ValueError(f"{path}: need 16 kHz mono, got {f.samplerate} Hz x{f.channels}")
        while True:
            x = f.read(block, dtype="float32")
            if not len(x):
                return
            yield x
