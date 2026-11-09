"""CHiME-6 dinner parties as speaker-test recordings (#271): the noisy-room set AMI lacks.

A session is ~2.5 hours with four people moving between kitchen, dining room and living room. We cut each session
into WINDOW-second windows (the last one absorbs a remainder shorter than half a window), and replay every window as
its own app session: a ten-minute conversation, a fresh speaker numbering, and the bootstrap's resampled unit
(4 people per session, so windows of one session are not independent people; the report says so).

Each window is heard by one Kinect array, channel 1: the array CHiME-6 names as the reference for most of that
window's utterances (the room where most of the talking happens), the closest match to one phone on a table. Speech
in other rooms stays in the reference and counts as missed, as in the CHiME-6 diarization track.

Reference times are the human utterance boundaries from the transcription JSON (no word alignment), so pauses inside
an utterance count as speech; DER levels are not comparable with AMI's word-level reference, only builds with builds.
"""
from __future__ import annotations

import json
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

from .reference import Seg

WINDOW = 600.0


def hms(t: str) -> float:
    h, m, s = t.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


@dataclass(frozen=True)
class Window:
    recording: str      # e.g. S01w03
    session: str
    array: str          # e.g. U06
    start: float        # in the session
    end: float


def utterances(path: Path) -> list[dict]:
    out = []
    for u in json.loads(Path(path).read_text()):
        s, e = hms(u["start_time"]), hms(u["end_time"])
        if e > s:
            out.append({"speaker": u["speaker"], "start": s, "end": e, "ref": u.get("ref"), "session": u["session_id"]})
    return out


def windows(utts: list[dict], session: str, window: float = WINDOW) -> list[Window]:
    end = max(u["end"] for u in utts)
    edges = [k * window for k in range(int(end // window) + 1)]
    if end - edges[-1] < window / 2 and len(edges) > 1:
        edges.pop()
    edges.append(end)
    out = []
    for k, (a, b) in enumerate(zip(edges, edges[1:])):
        refs = Counter()
        for u in utts:
            o = min(b, u["end"]) - max(a, u["start"])
            if o > 0 and u["ref"]:
                refs[u["ref"]] += o
        array = refs.most_common(1)[0][0] if refs else "U01"
        out.append(Window(f"{session}w{k:02d}", session, array, a, b))
    return out


def window_reference(utts: list[dict], w: Window) -> list[Seg]:
    """The window's speech in window-local seconds (0 = window start)."""
    out = []
    for u in utts:
        s, e = max(u["start"], w.start), min(u["end"], w.end)
        if e > s:
            out.append(Seg(u["speaker"], s - w.start, e - w.start))
    return sorted(out, key=lambda s: (s.start, s.end, s.speaker))


def write_reference(transcripts: Path, sessions: list[str], out: Path) -> list[Window]:
    """RTTM + UEM per window (same layout as AMI's, so the scorer needs nothing new) and windows.json for cutting
    the audio. `transcripts` is the folder holding <split>/<session>.json."""
    (out / "rttm").mkdir(parents=True, exist_ok=True)
    (out / "uem").mkdir(parents=True, exist_ok=True)
    allw = []
    for sess in sessions:
        path = next(Path(transcripts).glob(f"*/{sess}.json"))
        utts = utterances(path)
        for w in windows(utts, sess):
            ref = window_reference(utts, w)
            (out / "rttm" / f"{w.recording}.rttm").write_text("".join(
                f"SPEAKER {w.recording} 1 {s.start:.3f} {s.end - s.start:.3f} <NA> <NA> {s.speaker} <NA> <NA>\n" for s in ref))
            (out / "uem" / f"{w.recording}.uem").write_text(f"{w.recording} 1 0.000 {w.end - w.start:.3f}\n")
            allw.append(w)
    (out / "windows.json").write_text(json.dumps([w.__dict__ for w in allw], indent=1))
    return allw
