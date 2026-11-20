"""Held-out EdAcc calibration split and paired scoring (#272 "Parakeet Ultra smaller with no loss").

Calibration and fine-tuning must never touch a scored clip. EdAcc's own validation (62 speakers) and test (60) splits
share no speaker, so the calibration split is a handful of *validation* conversations (both speakers of each, so no conversation is
both calibrated on and scored), picked by a seeded hash, no accent twice and never an accent's last scored speaker. Everything else is the scored test set; EdAcc's own test
split (which a later fine-tuning step can train beside) is reported too.

The record (docs/perf/edacc-heldout-split.json) lists the calibration speakers and a digest of their clip ids, so a
hand edit or a different corpus build is caught on load.

Builds are compared on the same clips with a paired speaker bootstrap of the WER difference: speakers are resampled
once per draw and both systems scored on the same draw, which removes the between-speaker spread that dominates each
system's own interval (#145, #150 used the unpaired interval per engine).
"""
from __future__ import annotations

import hashlib
import json
import math
import random
from collections import Counter
from pathlib import Path
from typing import Mapping

SEED = 272
PARTS = ("calibration", "test", "edacc-test")


def _rank(seed: int, speaker: str) -> str:
    return hashlib.sha256(f"{seed}:{speaker}".encode()).hexdigest()


def conversation_of(speaker: str) -> str:
    """EDACC-C04-A and EDACC-C04-B are the two sides of one recorded conversation."""
    return speaker[:-2] if len(speaker) > 2 and speaker[-2] == "-" and speaker[-1] in "AB" else speaker


def choose_calibration_speakers(rows: list[dict], n: int = 12, seed: int = SEED, split: str = "validation") -> list[str]:
    """About n speakers from `split`, taken a whole conversation at a time (both sides, so no conversation is both
    calibrated on and scored), in seeded-hash order. A conversation is skipped if it would reuse an accent already
    held out or leave any accent with no scored speaker."""
    accent_of = {r["speaker"]: r["accent"] for r in rows}
    split_of = {r["speaker"]: r["split"] for r in rows}
    convs: dict[str, list[str]] = {}
    for spk in accent_of:
        convs.setdefault(conversation_of(spk), []).append(spk)
    left = Counter(accent_of.values())
    taken: list[str] = []
    used_accents: set[str] = set()
    for conv in sorted(convs, key=lambda c: _rank(seed, c)):
        if len(taken) >= n:
            break
        members = convs[conv]
        if any(split_of[s] != split for s in members):
            continue
        accs = Counter(accent_of[s] for s in members)
        if any(a in used_accents or left[a] - k < 1 for a, k in accs.items()):
            continue
        taken += members
        used_accents |= set(accs)
        left.subtract(accs)
    return sorted(taken)


def _digest(clip_ids) -> str:
    return hashlib.sha256("\n".join(sorted(clip_ids)).encode()).hexdigest()


def _summary(rows: list[dict]) -> dict:
    return {"speakers": len({r["speaker"] for r in rows}), "clips": len(rows),
            "hours": round(sum(float(r["audio_seconds"]) for r in rows) / 3600, 3),
            "accents": len({r["accent"] for r in rows})}


def split_record(rows: list[dict], calibration_speakers: list[str], seed: int = SEED) -> dict:
    cal = set(calibration_speakers)
    cal_rows = [r for r in rows if r["speaker"] in cal]
    test_rows = [r for r in rows if r["speaker"] not in cal]
    edacc_test = [r for r in test_rows if r["split"] == "test"]
    return {
        "method": (f"Calibration = whole EdAcc validation conversations (both speakers) in sha256('{seed}:conversation') "
                   "order, no accent twice, never an accent's last scored speaker; test = every other clip. "
                   "Speaker- and conversation-disjoint."),
        "seed": seed,
        "calibration": {**_summary(cal_rows), "speakers": sorted(cal), "speaker_count": len(cal),
                        "clip_digest": _digest(r["clip_id"] for r in cal_rows),
                        "accents_list": sorted({r["accent"] for r in cal_rows})},
        "test": {**_summary(test_rows), "clip_digest": _digest(r["clip_id"] for r in test_rows)},
        "edacc-test": {**_summary(edacc_test), "clip_digest": _digest(r["clip_id"] for r in edacc_test)},
    }


def load_split(path: Path, rows: list[dict] | None = None) -> dict:
    """Read a split record; refuse it if the speaker list no longer matches its digest (or the given manifest)."""
    rec = json.loads(Path(path).read_text(encoding="utf-8"))
    cal = rec["calibration"]
    if len(cal["speakers"]) != cal["speaker_count"]:
        raise ValueError(f"{path}: {len(cal['speakers'])} calibration speakers listed, record says {cal['speaker_count']}")
    if rows is not None:
        got = split_record(rows, cal["speakers"], rec["seed"])
        for part in PARTS:
            if got[part]["clip_digest"] != rec[part]["clip_digest"]:
                raise ValueError(f"{path}: the {part} clips differ from the manifest given (different corpus build?)")
    return rec


def filter_manifest(rows: list[dict], rec: dict, part: str) -> list[dict]:
    if part not in PARTS:
        raise ValueError(f"part must be one of {PARTS}, not {part!r}")
    cal = set(rec["calibration"]["speakers"])
    if part == "calibration":
        return [r for r in rows if r["speaker"] in cal]
    out = [r for r in rows if r["speaker"] not in cal]
    return [r for r in out if r["split"] == "test"] if part == "edacc-test" else out


def paired_diff_ci(a: Mapping[str, tuple[int, int]], b: Mapping[str, tuple[int, int]], n_boot: int = 2000,
                   seed: int = SEED, alpha: float = 0.05) -> tuple[float, float, float]:
    """WER(a) - WER(b) and its 95% percentile CI, both scored on the same resampled speakers each draw.

    a, b: speaker -> (errors, reference words), same speakers and the same clips behind them. O(n_boot * speakers).
    """
    if set(a) != set(b):
        raise ValueError(f"paired comparison needs the same speakers ({len(set(a) ^ set(b))} differ)")
    keys = sorted(a)
    for k in keys:
        if a[k][1] != b[k][1]:
            raise ValueError(f"speaker {k}: {a[k][1]} vs {b[k][1]} reference words; not the same clips")
    ea = [a[k][0] for k in keys]; eb = [b[k][0] for k in keys]; nn = [a[k][1] for k in keys]
    total = sum(nn)
    if not total:
        return math.nan, math.nan, math.nan
    d = (sum(ea) - sum(eb)) / total
    rng = random.Random(seed)
    m = len(keys)
    stats = []
    for _ in range(n_boot):
        de = n = 0
        for _ in range(m):
            i = rng.randrange(m)
            de += ea[i] - eb[i]; n += nn[i]
        if n:
            stats.append(de / n)
    stats.sort()
    lo = stats[int(math.floor((alpha / 2) * (len(stats) - 1)))]
    hi = stats[int(math.ceil((1 - alpha / 2) * (len(stats) - 1)))]
    return d, lo, hi


def heldout_scores(manifest_rows: list[dict], result_rows: list[dict], rec: dict, ref: str,
                   models: list[str] | None = None) -> dict:
    """part -> model -> WER, CI, counts, and the paired difference to `ref` on the same clips.

    Only first-repeat Parakeet result lines are used, keyed by model name. Clips are those every listed model has.
    """
    from .normalize import normalize
    from .wer import align_counts, bootstrap_ci

    by_model: dict[str, dict[str, str]] = {}
    for r in result_rows:
        if int(r.get("repeat", 1)) != 1:
            continue
        by_model.setdefault(str(r["model"]), {})[r["clip_id"]] = r["hypothesis"]
    models = models or sorted(by_model)
    if ref not in by_model:
        raise ValueError(f"reference model {ref!r} has no results")
    missing = [m for m in models if m not in by_model]
    if missing:
        raise ValueError(f"no results for {missing}")
    if ref not in models:
        models = [ref] + models
    out: dict = {}
    for part in ("test", "edacc-test"):
        clips = {r["clip_id"]: r for r in filter_manifest(manifest_rows, rec, part)}
        common = sorted(c for c in clips if all(c in by_model[m] for m in models))
        per: dict[str, dict[str, tuple[int, int]]] = {}
        cells = {}
        for m in models:
            spk: dict[str, list[int]] = {}
            sub = dele = ins = 0
            for c in common:
                k = align_counts(normalize(clips[c]["reference"]), normalize(by_model[m][c]))
                acc = spk.setdefault(clips[c]["speaker"], [0, 0])
                acc[0] += k.errors; acc[1] += k.n
                sub += k.sub; dele += k.dele; ins += k.ins
            groups = {s: (e, n) for s, (e, n) in spk.items()}
            per[m] = groups
            e = sum(v[0] for v in groups.values()); n = sum(v[1] for v in groups.values())
            lo, hi = bootstrap_ci(groups)
            cells[m] = {"wer": e / n if n else math.nan, "ci": [lo, hi], "sub": sub, "del": dele, "ins": ins,
                        "words": n, "clips": len(common), "speakers": len(groups)}
        for m in models:
            cells[m]["vs_ref"] = list(paired_diff_ci(per[m], per[ref]))
        out[part] = cells
    out["ref"] = ref
    return out
