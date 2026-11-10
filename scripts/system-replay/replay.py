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
import array
import hashlib
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


# --- noise --------------------------------------------------------------------------------------------------------

def noise_env(conversation_id: str, envs: list[str], seed: int = 273) -> str:
    """Which room a conversation is mixed into: a hash of its id, so it never depends on WER, order or the run."""
    h = hashlib.sha256(f"{seed}:{conversation_id}".encode()).digest()
    return envs[int.from_bytes(h[:8], "big") % len(envs)]


def _pcm16(path: Path) -> array.array:
    with wave.open(str(path)) as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2 or w.getframerate() != RATE:
            raise ValueError(f"{path}: want 16 kHz 16-bit mono")
        a = array.array("h", w.readframes(w.getnframes()))
    if sys.byteorder == "big":
        a.byteswap()
    return a


def mix(conversations: Path, noise_dir: Path, envs: list[str], out: Path, snr_db: float, split: str,
        seed: int = 273) -> list[dict]:
    """Each stitched conversation mixed with real room noise (noise_dir/<ENV>.wav, 16 kHz mono) at `snr_db`, the
    speech power measured over its segments only and the noise power over the whole excerpt. The noise runs through
    the gaps and tail too, so a room is never digitally silent. The excerpt starts at a seeded offset and loops if
    the recording is longer. References and segment times are unchanged. Writes <id>.16k.wav and the conversations
    file; `to48k` makes the replay copies on a Mac. Levels and rooms are fixed before any scored run (design doc)."""
    src = conversations.parent
    convs = [json.loads(l) for l in conversations.read_text().splitlines() if l.strip()]
    noises = {e: _pcm16(noise_dir / f"{e}.wav") for e in envs}
    out.mkdir(parents=True, exist_ok=True)
    result = []
    for c in convs:
        x = _pcm16(src / c["file16k"])
        env = noise_env(c["id"], envs, seed)
        n = noises[env]
        offset = random.Random(f"{seed}:{c['id']}:offset").randrange(len(n))
        excerpt = [n[(offset + i) % len(n)] for i in range(len(x))]
        idx = [i for s in c["segments"] for i in range(int(s["start"] * RATE), min(len(x), int(s["end"] * RATE)))]
        ps = sum(x[i] * x[i] for i in idx) / len(idx)
        pn = sum(v * v for v in excerpt) / len(excerpt)
        if ps == 0 or pn == 0:
            raise ValueError(f"{c['id']}: silent speech or noise, can't set an SNR")
        g = math.sqrt(ps / (pn * 10 ** (snr_db / 10)))
        y = array.array("h")
        clipped = 0
        for a, b in zip(x, excerpt):
            v = round(a + g * b)
            if v > 32767 or v < -32768:
                clipped += 1
                v = max(-32768, min(32767, v))
            y.append(v)
        if sys.byteorder == "big":
            y.byteswap()
        with wave.open(str(out / c["file16k"]), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(y.tobytes())
        c = dict(c, noise={"env": env, "snr_db": snr_db, "offset_seconds": round(offset / RATE, 3),
                           "gain": round(g, 6), "clipped_samples": clipped})
        result.append(c)
    (out / f"conversations-{split}.jsonl").write_text("".join(json.dumps(c) + "\n" for c in result))
    return result


def to48k(conversations: Path) -> int:
    """The 48 kHz Float32 replay copy of every conversation's 16 kHz file (afconvert, macOS), as the stitcher does."""
    d = conversations.parent
    k = 0
    for l in conversations.read_text().splitlines():
        if l.strip():
            c = json.loads(l)
            subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEF32@48000", "-c", "1", str(d / c["file16k"]),
                            str(d / c["file"])], check=True)
            k += 1
    return k


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


def language_gate(english: Mapping, saved: Mapping[str, Mapping], max_gap: float, n_boot: int = 1000) -> dict:
    """#273's regression case: English speech with a non-English caption language saved in Seal. For each saved
    language, the paired WER gap against the same build with en-US, on the same conversations. It fails when the
    gap's 95% CI lies wholly above `max_gap` (the data is sure the saved language costs more than that), so a noisy
    small rise doesn't fail it and a real one does. The 2-point margin was set from the published dev-split locale
    run (build 9, Apple's engine in the saved language: CIs from +26 points up; build 10: lower bounds 0 or below)
    and is fixed from here on; it is never set from the test split."""
    out, passed = {}, True
    for lang, arm in saved.items():
        if set(arm["counts"]) != set(english["counts"]):
            raise ValueError(f"{lang}: not the same conversations as en-US")
        g = paired_gap({c: (tuple(english["counts"][c]), tuple(arm["counts"][c])) for c in english["counts"]},
                       n_boot=n_boot)
        g["failed"] = g["lo"] > max_gap
        passed = passed and not g["failed"]
        out[lang] = g
    return {"passed": passed, "max_gap": max_gap, "languages": out}


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


def by_fallback(results: Mapping[str, Mapping], arm: str, refs: list[str], n_boot: int = 1000) -> dict:
    """For an arm whose sessions sometimes left Parakeet: its sessions that stayed on Parakeet and those that left,
    each paired with every reference arm on exactly those conversations. The split comes from the arm's own run
    record (plan, fallbacks, engines seen), never from its WER, so it is a stratification, not a selection."""
    left = set(results[arm]["left_parakeet"])
    if not left:
        return {}
    out: dict[str, dict] = {}
    for ref in refs:
        parts = {}
        for label, keep in (("stayed on Parakeet", False), ("left Parakeet", True)):
            ids = [c for c in results[arm]["counts"] if (c in left) == keep]
            if ids:
                parts[label] = paired_gap({c: (tuple(results[ref]["counts"][c]), tuple(results[arm]["counts"][c]))
                                           for c in ids}, n_boot=n_boot)
        out[ref] = parts
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
    refs = [names[0]] + [n for n in names if n.startswith("engine-only")]
    split = {a: by_fallback(results, a, [r for r in refs if r != a], n_boot=n_boot) for a in names}
    split = {a: v for a, v in split.items() if v}
    for r in results.values():
        r["ci"] = paired_gap({cid: (v, v) for cid, v in r["counts"].items()}, n_boot=n_boot)["a_ci"]
        r["counts"] = {k: list(v) for k, v in r["counts"].items()}
    return {"conversations": len(convs), "audio_minutes": round(sum(c["audio_seconds"] for c in convs) / 60, 1),
            "speakers": len({s for c in convs for s in c["speakers"]}), "arms": results, "paired": pairs,
            "by_fallback": split}


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
    if res.get("by_fallback"):
        lines += ["", "Arms that left Parakeet mid-session, split by their own engine record (WER of each part, "
                  "paired with the reference on the same conversations):", "",
                  "| Arm | Part | Conversations | Arm WER | Reference | Reference WER | Arm minus reference | 95% CI |",
                  "|---|---|---|---|---|---|---|---|"]
        for arm, refs in res["by_fallback"].items():
            for ref, parts in refs.items():
                for part, g in parts.items():
                    lines.append(f"| {arm} | {part} | {g['units']} | {_pct(g['b'])} | {ref} | {_pct(g['a'])} | "
                                 f"{100 * g['gap']:+.1f} | {100 * g['lo']:+.1f} to {100 * g['hi']:+.1f} |")
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
    m = sub.add_parser("mix")
    m.add_argument("--conversations", type=Path, required=True)
    m.add_argument("--noise", type=Path, required=True, help="dir of <ENV>.wav, 16 kHz mono")
    m.add_argument("--env", action="append", required=True)
    m.add_argument("--snr", type=float, required=True)
    m.add_argument("--split", choices=["test", "validation"], required=True)
    m.add_argument("--out", type=Path, required=True)
    t = sub.add_parser("to48k")
    t.add_argument("--conversations", type=Path, required=True)
    c = sub.add_parser("score")
    c.add_argument("--conversations", type=Path, required=True)
    c.add_argument("--arm", action="append", default=[], help="NAME=SESSIONS_DIR")
    c.add_argument("--engine-only", type=Path)
    c.add_argument("--out", type=Path, required=True)
    c.add_argument("--markdown", type=Path)
    g = sub.add_parser("gate-language", help="#273: fail if a saved non-English caption language hurts English")
    g.add_argument("--conversations", type=Path, required=True)
    g.add_argument("--english", type=Path, required=True, help="sessions run with caption language en-US")
    g.add_argument("--saved", action="append", required=True, help="LANG=SESSIONS_DIR, the same build and audio")
    g.add_argument("--max-gap", type=float, default=0.02, help="WER points as a fraction (fixed before any run)")
    g.add_argument("--out", type=Path)
    a = p.parse_args(argv)
    if a.cmd == "gate-language":
        convs = [json.loads(l) for l in a.conversations.read_text().splitlines() if l.strip()]
        english = score_arm(convs, load_sessions(a.english))
        saved = {x.split("=", 1)[0]: score_arm(convs, load_sessions(Path(x.split("=", 1)[1]))) for x in a.saved}
        res = language_gate(english, saved, a.max_gap)
        if a.out:
            a.out.write_text(json.dumps(res, indent=1, sort_keys=True))
        print(f"en-US {_pct(english['wer'])} on {len(convs)} conversations; fails above +{100 * a.max_gap:.1f} points")
        for lang, r in res["languages"].items():
            print(f"  {lang}: {_pct(r['b'])}, {100 * r['gap']:+.1f} points (95% CI {100 * r['lo']:+.1f} to "
                  f"{100 * r['hi']:+.1f}) {'FAIL' if r['failed'] else 'ok'}")
        print("PASS" if res["passed"] else "FAIL: a saved caption language makes English captions worse")
        return 0 if res["passed"] else 1
    if a.cmd == "stitch":
        if a.to48k and not shutil.which("afconvert"):
            print("afconvert not found (macOS only)", file=sys.stderr)
            return 2
        convs = stitch(a.shard, a.out, a.split, a.gap, a.tail, to48k=a.to48k)
        print(f"{len(convs)} conversations, {sum(c['audio_seconds'] for c in convs) / 60:.1f} min -> {a.out}")
        return 0
    if a.cmd == "mix":
        convs = mix(a.conversations, a.noise, a.env, a.out, a.snr, a.split)
        print(f"{len(convs)} conversations at {a.snr:+.0f} dB -> {a.out}; "
              f"rooms {dict(Counter(c['noise']['env'] for c in convs))}; "
              f"clipped samples {sum(c['noise']['clipped_samples'] for c in convs)}")
        return 0
    if a.cmd == "to48k":
        if not shutil.which("afconvert"):
            print("afconvert not found (macOS only)", file=sys.stderr)
            return 2
        print(f"{to48k(a.conversations)} files converted")
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
