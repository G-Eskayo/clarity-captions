"""Whole-system replay (#273): stitch EdAcc conversations, score replayed sessions against each other and against the
engine-only numbers. docs/perf/whole-system-replay-design.md.

  python3 -I replay.py stitch --shard DIR --out DIR --split test|validation
  python3 -I replay.py score  --conversations conversations-test.jsonl --arm NAME=SESSIONS_DIR ... \
                              [--engine-only RESULTS.jsonl] --out results.json [--markdown results.md]

Normalisation and WER are #145's own (scripts/engine-eval/edacc_eval), so a whole-system number and the engine-only
number for the same clips are scored by one rule. Stdlib only, plus edacc_eval.
"""
from __future__ import annotations

import argparse
import json
import math
import random
import re
import shutil
import struct
import subprocess
import sys
import wave
from collections import Counter
from pathlib import Path
from typing import Mapping

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "engine-eval"))
from edacc_eval.normalize import normalize  # noqa: E402
from edacc_eval.wer import align_counts  # noqa: E402

RATE = 16_000
_CLIP = re.compile(r"^(test|validation)-(.+)-(\d+)$")


def conversation_of(clip_id: str) -> tuple[str, int]:
    """("EDACC-C34", 9) from "test-EDACC-C34-9". The source file stem is the conversation, the number its segment."""
    m = _CLIP.match(clip_id)
    if not m:
        raise ValueError(f"not an EdAcc clip id: {clip_id!r}")
    return m.group(2), int(m.group(3))


def _read16k(path: Path, want_seconds: float) -> bytes:
    with wave.open(str(path)) as w:
        if w.getframerate() != RATE or w.getnchannels() != 1 or w.getsampwidth() != 2:
            raise ValueError(f"{path.name}: want 16 kHz mono 16-bit, got {w.getframerate()} Hz x{w.getnchannels()}")
        frames = w.readframes(w.getnframes())
    got = len(frames) / 2 / RATE
    if abs(got - want_seconds) > 0.02:   # the manifest rounds to 0.01 s
        raise ValueError(f"{path.name}: audio length {got:.3f} s, manifest says {want_seconds} s")
    return frames


def stitch(shard: Path, out: Path, split: str, gap_seconds: float, tail_seconds: float,
           to48k: bool = False) -> list[dict]:
    """One recording per conversation: its `split` segments in this shard, in segment order, `gap_seconds` of silence
    between, `tail_seconds` after (the quiet before she taps Stop). Segments #145 doesn't score (empty after
    normalisation, IGNORE_TIME_SEGMENT_IN_SCORING) are left out of the audio too. Gap and tail are fixed before any
    scored run (design doc); they are never tuned on scored clips. With `to48k`, also writes the 48 kHz Float32 copy
    the iPhone's microphone would hand over (afconvert), which is what the harness replays."""
    rows = [json.loads(l) for l in (shard / "manifest.jsonl").read_text().splitlines() if l.strip()]
    groups: dict[str, list[tuple[int, dict]]] = {}
    for r in rows:
        if r["split"] != split or not normalize(r["reference"]):
            continue
        conv, seg = conversation_of(r["clip_id"])
        groups.setdefault(conv, []).append((seg, r))
    out.mkdir(parents=True, exist_ok=True)
    gap = b"\0\0" * int(gap_seconds * RATE)
    convs = []
    for conv in sorted(groups):
        t = 0.0
        pcm = bytearray()
        segments = []
        for i, (_, r) in enumerate(sorted(groups[conv], key=lambda x: x[0])):
            if i:
                pcm += gap
                t += gap_seconds
            frames = _read16k(shard / r["file"], r["audio_seconds"])
            secs = len(frames) / 2 / RATE
            segments.append({"clip_id": r["clip_id"], "speaker": r["speaker"], "accent": r["accent"],
                             "reference": r["reference"], "start": round(t, 6), "end": round(t + secs, 6)})
            pcm += frames
            t += secs
        pcm += b"\0\0" * int(tail_seconds * RATE)
        cid = f"{split}-{conv}"
        f16 = f"{cid}.16k.wav"
        with wave.open(str(out / f16), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(bytes(pcm))
        c = {"id": cid, "conversation": conv, "split": split, "file16k": f16,
             "file": f"{cid}.48k.wav" if to48k else f16,
             "speakers": sorted({s["speaker"] for s in segments}), "accents": sorted({s["accent"] for s in segments}),
             "audio_seconds": round(len(pcm) / 2 / RATE, 3), "gap_seconds": gap_seconds, "tail_seconds": tail_seconds,
             "reference": " ".join(normalize(s["reference"]) for s in segments), "segments": segments}
        if to48k:
            subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEF32@48000", "-c", "1", str(out / f16), str(out / c["file"])],
                           check=True)
        convs.append(c)
    (out / f"conversations-{split}.jsonl").write_text("".join(json.dumps(c) + "\n" for c in convs))
    return convs


# --- scoring ----------------------------------------------------------------------------------------------------

def session_text(log: Mapping) -> str:
    """What she read: the caption lines as the app's CaptionStream built them, sound labels left out."""
    if log.get("error"):
        raise ValueError(f"session has an error ({log['error']}): rerun it, don't score it as silence")
    return " ".join(l["text"] for l in log.get("lines", []) if not l.get("soundLabel") and l.get("text"))


def percentile(xs: list[float], q: float) -> float:
    """Linear-interpolated percentile; nan for an empty list."""
    if not xs:
        return math.nan
    s = sorted(xs)
    k = (len(s) - 1) * q
    lo, hi = math.floor(k), math.ceil(k)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def score_arm(convs: list[dict], logs: Mapping[str, Mapping]) -> dict:
    """Pooled WER over every conversation (errors over reference words), with what ran: sessions that left
    Parakeet, every fallback reason, and the engine's own word lag (ADR 0015) pooled over sessions."""
    counts: dict[str, tuple[int, int]] = {}
    left, reasons, lags, line_lags = [], Counter(), [], []
    for c in convs:
        log = logs.get(c["id"])
        if log is None:
            raise ValueError(f"session missing for {c['id']}")
        k = align_counts(normalize(c["reference"]), normalize(session_text(log)))
        counts[c["id"]] = (k.errors, k.n)
        plan = log.get("plan") or {}
        seen = [e["name"] for e in log.get("enginesSeen", [])]
        if plan.get("engine") == "parakeet" and (log.get("fallbacks") or any(not n.startswith("parakeet") for n in seen)):
            left.append(c["id"])
        for f in log.get("fallbacks", []):
            reasons[f["reason"]] += 1
        for u in log.get("updates", []):
            if u.get("lag") is not None:
                lags.append(u["lag"])
            if u.get("isFinal") and u.get("end") is not None and log.get("path") == "source":
                line_lags.append(u["at"] - u["end"])
    e = sum(v[0] for v in counts.values())
    n = sum(v[1] for v in counts.values())
    return {"counts": counts, "wer": e / n if n else math.nan, "errors": e, "words": n, "left_parakeet": left,
            "fallback_reasons": dict(reasons), "word_lag_p50": percentile(lags, 0.5), "word_lag_p95": percentile(lags, 0.95),
            "line_lag_p50": percentile(line_lags, 0.5), "line_lag_p95": percentile(line_lags, 0.95),
            "lag_samples": len(lags)}


def paired_gap(units: Mapping[str, tuple[tuple[int, int], tuple[int, int]]], n_boot: int = 1000, seed: int = 273,
               alpha: float = 0.05) -> dict:
    """WER of arm b minus arm a on the same conversations, with a 95% percentile bootstrap that resamples
    conversations (each one's pair together: same audio, same speakers), the #145 rule applied to paired arms.
    units: conversation -> ((errors_a, words_a), (errors_b, words_b)). Also each arm's own CI. O(n_boot * units)."""
    items = list(units.values())
    def wer(sel, arm):
        e = sum(x[arm][0] for x in sel)
        n = sum(x[arm][1] for x in sel)
        return e / n if n else math.nan
    a, b = wer(items, 0), wer(items, 1)
    rng = random.Random(seed)
    gaps, was, wbs = [], [], []
    k = len(items)
    for _ in range(n_boot):
        sel = [items[rng.randrange(k)] for _ in range(k)]
        wa, wb = wer(sel, 0), wer(sel, 1)
        if not (math.isnan(wa) or math.isnan(wb)):
            gaps.append(wb - wa); was.append(wa); wbs.append(wb)
    def ci(xs):
        if not xs:
            return math.nan, math.nan
        xs = sorted(xs)
        return xs[int(math.floor((alpha / 2) * (len(xs) - 1)))], xs[int(math.ceil((1 - alpha / 2) * (len(xs) - 1)))]
    lo, hi = ci(gaps)
    return {"a": a, "b": b, "gap": b - a, "lo": lo, "hi": hi, "a_ci": ci(was), "b_ci": ci(wbs), "units": k}


def engine_only_logs(convs: list[dict], rows: list[dict], engine: str, model: str) -> dict[str, dict]:
    """The #145 engine-only hypotheses (whole clip files, FileTranscriber) for the same clips, joined per
    conversation in segment order, shaped like a session log so the same scorer reads them. Repeat 1 only."""
    hyp = {r["clip_id"]: r["hypothesis"] for r in rows
           if r["engine"] == engine and r["model"] == model and r.get("repeat", 1) == 1}
    out = {}
    for c in convs:
        texts = []
        for s in c["segments"]:
            if s["clip_id"] not in hyp:
                raise ValueError(f"no engine-only row for {s['clip_id']} ({engine} {model})")
            texts.append(hyp[s["clip_id"]] or "")
        out[c["id"]] = {"lines": [{"text": " ".join(t for t in texts if t), "soundLabel": None}],
                        "plan": {"engine": engine}, "enginesSeen": [], "fallbacks": [], "updates": []}
    return out


def load_sessions(d: Path) -> dict[str, dict]:
    return {p.stem: json.loads(p.read_text()) for p in sorted(d.glob("*.json"))}


def _pct(x: float) -> str:
    return "n/a" if x is None or (isinstance(x, float) and math.isnan(x)) else f"{100 * x:.1f}%"


def _s(x: float) -> str:
    return "n/a" if x is None or (isinstance(x, float) and math.isnan(x)) else f"{x:.2f} s"


def score(conversations: Path, arms: list[tuple[str, Path]], engine_only: Path | None, n_boot: int = 1000) -> dict:
    convs = [json.loads(l) for l in conversations.read_text().splitlines() if l.strip()]
    results: dict[str, dict] = {}
    for name, d in arms:
        results[name] = score_arm(convs, load_sessions(d))
    if engine_only:
        rows = [json.loads(l) for l in engine_only.read_text().splitlines() if l.strip()]
        results["engine-only Parakeet (ultra-pal6, #145)"] = score_arm(
            convs, engine_only_logs(convs, rows, "parakeet-fluidaudio", "ultra-pal6"))
        results["engine-only Apple (SpeechTranscriber en-US, #145)"] = score_arm(
            convs, engine_only_logs(convs, rows, "apple-speechanalyzer", "SpeechTranscriber en-US"))
    names = list(results)
    pairs = {}
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            units = {cid: (results[a]["counts"][cid], results[b]["counts"][cid]) for cid in results[a]["counts"]}
            pairs[f"{b} minus {a}"] = paired_gap(units, n_boot=n_boot)
    for r in results.values():
        r["ci"] = paired_gap({cid: (v, v) for cid, v in r["counts"].items()}, n_boot=n_boot)["a_ci"]
        r["counts"] = {k: list(v) for k, v in r["counts"].items()}
    return {"conversations": len(convs), "audio_minutes": round(sum(c["audio_seconds"] for c in convs) / 60, 1),
            "speakers": len({s for c in convs for s in c["speakers"]}), "arms": results, "paired": pairs}


def markdown(res: dict) -> str:
    lines = [f"{res['conversations']} conversations, {res['speakers']} speakers, {res['audio_minutes']} minutes of audio. "
             "WER pooled over conversations; 95% CIs resample conversations (1,000 resamples).", "",
             "| Arm | WER | 95% CI | Words | Left Parakeet | Fallbacks | Word lag p50 / p95 | Finished-line lag p50 / p95 |",
             "|---|---|---|---|---|---|---|---|"]
    for name, r in res["arms"].items():
        fb = ", ".join(f"{k} x{v}" for k, v in r["fallback_reasons"].items()) or "none"
        lines.append(f"| {name} | {_pct(r['wer'])} | {_pct(r['ci'][0])} to {_pct(r['ci'][1])} | {r['words']} | "
                     f"{len(r['left_parakeet'])} | {fb} | {_s(r['word_lag_p50'])} / {_s(r['word_lag_p95'])} | "
                     f"{_s(r['line_lag_p50'])} / {_s(r['line_lag_p95'])} |")
    lines += ["", "Paired differences (same conversations; a CI that excludes 0 is a real difference):", "",
              "| Difference | WER points | 95% CI |", "|---|---|---|"]
    for name, g in res["paired"].items():
        lines.append(f"| {name} | {100 * g['gap']:+.1f} | {100 * g['lo']:+.1f} to {100 * g['hi']:+.1f} |")
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("stitch")
    s.add_argument("--shard", type=Path, required=True)
    s.add_argument("--out", type=Path, required=True)
    s.add_argument("--split", choices=["test", "validation"], required=True)
    s.add_argument("--gap", type=float, default=1.0)
    s.add_argument("--tail", type=float, default=3.0)
    s.add_argument("--48k", dest="to48k", action="store_true")
    c = sub.add_parser("score")
    c.add_argument("--conversations", type=Path, required=True)
    c.add_argument("--arm", action="append", default=[], help="NAME=SESSIONS_DIR")
    c.add_argument("--engine-only", type=Path)
    c.add_argument("--out", type=Path, required=True)
    c.add_argument("--markdown", type=Path)
    a = p.parse_args(argv)
    if a.cmd == "stitch":
        if a.to48k and not shutil.which("afconvert"):
            print("afconvert not found (macOS only)", file=sys.stderr)
            return 2
        convs = stitch(a.shard, a.out, a.split, a.gap, a.tail, to48k=a.to48k)
        print(f"{len(convs)} conversations, {sum(c['audio_seconds'] for c in convs) / 60:.1f} min -> {a.out}")
        return 0
    arms = [(x.split("=", 1)[0], Path(x.split("=", 1)[1])) for x in a.arm]
    res = score(a.conversations, arms, a.engine_only)
    a.out.write_text(json.dumps(res, indent=1, sort_keys=True))
    md = markdown(res)
    if a.markdown:
        a.markdown.write_text(md)
    print(md)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
