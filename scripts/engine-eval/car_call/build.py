"""Build a car-call test set (#303) from clips the accuracy set already scores, references included.

Each pair is one far clip (the caller) and one near clip (someone in the car, from a different conversation).
Per pair it writes, as 16 kHz mono WAV plus a manifest the Swift engine-eval runner reads directly:

    clean-far   the far clip untouched: the engine's own baseline on this speech
    clean-near  the near clip untouched
    phone       far clip through the call + car speaker + cabin, nothing else (isolates the channel)
    snrNN       the full scene: call, then the near talker answering, over road noise at NN dB SNR

    python -m car_call.build --source ~/Library/Caches/seal-car-call/src --out ~/Library/Caches/seal-car-call/set \
        --pairs 30 --snrs 20,10,5,0 --seed 303
"""
from __future__ import annotations

import argparse
import json
import random
import shutil
import subprocess
import wave
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from edacc_eval.normalize import normalize

from . import chain
from .score import conversation

SR = 16000


@dataclass(frozen=True)
class Pair:
    far: dict
    near: dict


def _words(r: dict) -> int:
    return len(normalize(r["reference"]).split())


def select_pairs(rows: list[dict], *, n: int, seed: int, far_seconds=(6.0, 15.0), near_seconds=(2.5, 7.0),
                 min_far_words: int = 12, min_near_words: int = 6) -> list[Pair]:
    """One far clip per speaker, n speakers, each with a near clip from another conversation; no clip is
    used twice, as far or near. Deterministic for a seed, whatever the input order."""
    rows = sorted(rows, key=lambda r: r["clip_id"])
    far_ok = [r for r in rows if far_seconds[0] <= r["audio_seconds"] <= far_seconds[1]
              and _words(r) >= min_far_words]
    near_ok = [r for r in rows if near_seconds[0] <= r["audio_seconds"] <= near_seconds[1]
               and _words(r) >= min_near_words]
    rng = random.Random(seed)
    # A clip that fits both windows goes to one pool only, chosen by the seed, so no clip is heard twice.
    both = {r["clip_id"] for r in far_ok} & {r["clip_id"] for r in near_ok}
    to_near = {c for c in sorted(both) if rng.random() < 0.5}
    far_ok = [r for r in far_ok if r["clip_id"] not in to_near]
    near_ok = [r for r in near_ok if r["clip_id"] not in both - to_near]
    by_speaker: dict[str, list[dict]] = {}
    for r in far_ok:
        by_speaker.setdefault(r["speaker"], []).append(r)
    speakers = sorted(by_speaker)
    rng.shuffle(speakers)
    pairs: list[Pair] = []
    used: set[str] = set()
    for s in speakers:
        if len(pairs) == n:
            break
        far = rng.choice(by_speaker[s])
        cands = [r for r in near_ok if conversation(r["speaker"]) != conversation(s) and r["clip_id"] != far["clip_id"]]
        pool = [r for r in cands if r["clip_id"] not in used]
        if not pool:
            continue
        near = rng.choice(pool)
        used.add(near["clip_id"])
        pairs.append(Pair(far=far, near=near))
    if len(pairs) < n:
        raise ValueError(f"only {len(pairs)} usable pairs for {n} requested")
    return pairs


def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path)) as w:
        if (w.getframerate(), w.getnchannels(), w.getsampwidth()) != (SR, 1, 2):
            raise ValueError(f"{path}: expected 16 kHz mono 16-bit")
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32767


def write_wav(path: Path, x: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.round(np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


def _ffmpeg_version() -> str:
    try:
        return subprocess.run(["ffmpeg", "-version"], capture_output=True, text=True).stdout.splitlines()[0]
    except (OSError, IndexError):
        return "unavailable"


def build_set(pairs: list[Pair], source: Path, out: Path, *, snrs: list[float], seed: int, codec: str,
              near_gain_db: float = 6.0, gap_s: float = 0.4) -> list[dict]:
    chain.check_codec(codec)
    source, out = Path(source), Path(out)
    (out / "audio").mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []

    def row(pid: str, cond: str, pair: Pair, *, far: bool, near: bool, seconds: float, snr=None, spans=None):
        cid = f"{pid}-{cond}"
        r = {"clip_id": cid, "pair": pid, "condition": cond, "snr_db": snr, "file": f"audio/{cid}.wav",
             "accent": pair.far.get("accent", "") if far else pair.near.get("accent", ""),
             "speaker": pair.far["speaker"] if far else pair.near["speaker"],
             "far_clip": pair.far["clip_id"] if far else None, "near_clip": pair.near["clip_id"] if near else None,
             "far_reference": pair.far["reference"] if far else "",
             "near_reference": pair.near["reference"] if near else "",
             "audio_seconds": round(seconds, 3), "codec": codec if cond not in ("clean-far", "clean-near") else None}
        r["reference"] = " ".join(x for x in (r["far_reference"], r["near_reference"]) if x)
        if spans:
            r["far_span_s"] = [round(s / SR, 3) for s in spans[0]]
            r["near_span_s"] = [round(s / SR, 3) for s in spans[1]]
        rows.append(r)
        return out / r["file"]

    for i, p in enumerate(pairs):
        pid = f"cc{i + 1:03d}"
        far_src, near_src = source / p.far["file"], source / p.near["file"]
        shutil.copyfile(far_src, row(pid, "clean-far", p, far=True, near=False, seconds=p.far["audio_seconds"]))
        shutil.copyfile(near_src, row(pid, "clean-near", p, far=False, near=True, seconds=p.near["audio_seconds"]))
        far, near = read_wav(far_src), read_wav(near_src)
        conds: list[tuple[str, float | None, bool]] = [("phone", None, False)] + \
            [(f"snr{s:g}", float(s), True) for s in snrs]
        for k, (cond, snr, with_near) in enumerate(conds):
            rng = np.random.default_rng([seed, i, k])
            sc = chain.mix_scene(far, near if with_near else None, SR, rng, snr_db=snr, near_gain_db=near_gain_db,
                                 gap_s=gap_s, codec=codec)
            write_wav(row(pid, cond, p, far=True, near=with_near, seconds=len(sc.mix) / SR, snr=snr,
                          spans=(sc.far_span, sc.near_span)), sc.mix)
    with open(out / "manifest.jsonl", "w") as fh:
        for r in rows:
            fh.write(json.dumps(r, sort_keys=True) + "\n")
    (out / "set.json").write_text(json.dumps({
        "ticket": 303, "pairs": len(pairs), "snrs": list(snrs), "seed": seed, "codec": codec,
        "near_gain_db": near_gain_db, "gap_s": gap_s, "ffmpeg": _ffmpeg_version(),
        "clips": len(rows), "audio_seconds": round(sum(r["audio_seconds"] for r in rows), 1)}, indent=1) + "\n")
    return rows


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="build the #303 car-call set")
    ap.add_argument("--source", type=Path, required=True, help="dir with manifest.jsonl + the clips it names")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--pairs", type=int, default=30)
    ap.add_argument("--snrs", default="20,10,5,0")
    ap.add_argument("--seed", type=int, default=303)
    ap.add_argument("--codec", default=None, help=f"one of {chain.CODECS}; default: AMR-NB if ffmpeg has it")
    ap.add_argument("--near-gain-db", type=float, default=6.0)
    ap.add_argument("--select-only", action="store_true", help="print the chosen clips as JSON lines and stop")
    a = ap.parse_args(argv)
    rows = [json.loads(l) for l in (a.source / "manifest.jsonl").read_text().splitlines() if l.strip()]
    pairs = select_pairs(rows, n=a.pairs, seed=a.seed)
    if a.select_only:
        for p in pairs:
            print(json.dumps({"far": p.far["file"], "near": p.near["file"]}))
        return 0
    codec = a.codec or chain.best_codec()
    out = build_set(pairs, a.source, a.out, snrs=[float(s) for s in a.snrs.split(",")], seed=a.seed, codec=codec,
                    near_gain_db=a.near_gain_db)
    print(f"{len(out)} clips, {len(pairs)} pairs, codec {codec} -> {a.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
