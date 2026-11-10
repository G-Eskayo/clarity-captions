"""python -I -m speaker_onnx.paired --set ami --engine recogment-v2 --engine-results DIR --base fp16 --base-results DIR
   --rttm-dir DIR --uem-dir DIR --out-json PATH   (#160)

Engine minus baseline on the same test recordings, with a 95% CI from a paired bootstrap: each resample draws
recordings with replacement and scores both engines on the SAME draw, so the spread between meetings (much larger than
the gap between engines) cancels. Same resample count and seed as the #276 scoreboard (1,000, seed 271).
O(n_boot * k) for k recordings.
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path
from typing import Callable, Sequence

from speaker_eval import split as splitmod
from speaker_eval.cli import collect, reference
from speaker_eval.score import N_BOOT, SEED, RecScore, _quantile, load_result, pooled, score_recording, split_rate

Stat = Callable[[Sequence[RecScore]], float]


def paired_bootstrap(eng: Sequence[RecScore], base: Sequence[RecScore], stat: Stat, n: int = N_BOOT,
                     seed: int = SEED, alpha: float = 0.05) -> tuple[float, tuple[float, float]]:
    """stat(engine) - stat(baseline), and its percentile CI. Recordings are paired by name; both sides must match."""
    e = {r.recording: r for r in eng}
    b = {r.recording: r for r in base}
    if e.keys() != b.keys():
        raise ValueError(f"recordings differ: {sorted(e.keys() ^ b.keys())}")
    names = sorted(e)
    E, B = [e[k] for k in names], [b[k] for k in names]
    value = stat(E) - stat(B)
    rng = random.Random(seed)
    k = len(names)
    vals = []
    for _ in range(n):
        idx = [rng.randrange(k) for _ in range(k)]
        v = stat([E[i] for i in idx]) - stat([B[i] for i in idx])
        if v == v:
            vals.append(v)
    vals.sort()
    if not vals:
        return value, (float("nan"), float("nan"))
    return value, (_quantile(vals, alpha / 2), _quantile(vals, 1 - alpha / 2))


STATS: dict[str, Stat] = {
    "der_live_diff": lambda x: pooled(x, "live"),
    "der_bare_diff": lambda x: pooled(x, "bare"),
    "monologue_split_rate_diff": split_rate,
}


def paired_summary(eng: Sequence[RecScore], base: Sequence[RecScore]) -> dict:
    out: dict = {"recordings": len(eng)}
    for key, stat in STATS.items():
        v, (lo, hi) = paired_bootstrap(eng, base, stat)
        out[key] = {"value": v, "ci95": [lo, hi]}
    return out


def score_dir(results: Path, model: str, sp, rttm: Path, uem: Path) -> list[RecScore]:
    found = collect(results, model)
    for rec in found:
        sp.require_test(rec)
    missing = [r for r in sp.test if r not in found or 1 not in found[r]]
    if missing:
        raise SystemExit(f"{model}: missing repeat 1 for {', '.join(missing)}")
    out = []
    for rec in sp.test:
        ref, u, ph = reference(rec, rttm, uem)
        out.append(score_recording(load_result(found[rec][1]), ref, ph, u))
    return out


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="speaker_onnx.paired")
    p.add_argument("--set", default="ami")
    p.add_argument("--split", type=Path, default=splitmod.DEFAULT)
    p.add_argument("--rttm-dir", type=Path, required=True)
    p.add_argument("--uem-dir", type=Path, required=True)
    p.add_argument("--engine", required=True)
    p.add_argument("--engine-results", type=Path, required=True)
    p.add_argument("--base", required=True)
    p.add_argument("--base-results", type=Path, required=True)
    p.add_argument("--out-json", type=Path, required=True)
    a = p.parse_args(argv)
    sp = splitmod.load(a.split, a.set)
    eng = score_dir(a.engine_results, a.engine, sp, a.rttm_dir, a.uem_dir)
    base = score_dir(a.base_results, a.base, sp, a.rttm_dir, a.uem_dir)
    s = paired_summary(eng, base)
    s.update({"set": a.set, "engine": a.engine, "base": a.base, "method": "paired percentile bootstrap over "
              f"recordings, {N_BOOT} resamples, seed {SEED}"})
    a.out_json.parent.mkdir(parents=True, exist_ok=True)
    a.out_json.write_text(json.dumps(s, indent=1, sort_keys=True))
    d = s["der_live_diff"]
    print(f"{a.engine} - {a.base} ({a.set}): live DER {d['value']:+.2%} ({d['ci95'][0]:+.2%} to {d['ci95'][1]:+.2%})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
