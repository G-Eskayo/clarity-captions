"""A compressed build against fp16 on one test set (#271 step 2): both summaries, the paired difference, the ship rule.

The ticket's rule, per set: the build's DER-on-screen 95% CI overlaps fp16's, and its line first-label median is
within 10% of fp16's. A build ships only if it passes on both sets. Beside it, the paired bootstrap of build minus
fp16 (the same resampled recordings for both, seed 271), which is tighter than comparing two intervals because both
ran on the same audio.

  python -m speaker_eval.compare --set ami --base fp16 --model pal8 --rttm-dir D --uem-dir D --results D \
      --out-json F --out-md F
Repeat 1 of each is compared (the determinism row of `cli score` covers the repeats).
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from dataclasses import dataclass
from pathlib import Path

from . import split as splitmod
from .cli import collect, reference
from .score import N_BOOT, SEED, _quantile, line_delay, load_result, pooled, score_recording, split_rate, summary


@dataclass(frozen=True)
class Verdict:
    der_ci_overlaps: bool
    latency_within_10pct: bool

    @property
    def passes(self) -> bool:
        return self.der_ci_overlaps and self.latency_within_10pct


def paired_bootstrap(base, cand, stat, n: int = N_BOOT, seed: int = SEED, alpha: float = 0.05) -> tuple:
    """stat(cand) - stat(base) over the same resampled recordings: (value, lo, hi)."""
    if [r.recording for r in base] != [r.recording for r in cand]:
        raise ValueError("paired comparison needs the same recordings in the same order")
    v = stat(cand) - stat(base)
    rng = random.Random(seed)
    k = len(base)
    vals = []
    for _ in range(n):
        idx = [rng.randrange(k) for _ in range(k)]
        d = stat([cand[i] for i in idx]) - stat([base[i] for i in idx])
        if d == d:
            vals.append(d)
    vals.sort()
    return v, _quantile(vals, alpha / 2), _quantile(vals, 1 - alpha / 2)


def ship_rule(base_summary: dict, cand_summary: dict) -> Verdict:
    blo, bhi = base_summary["der_live"]["ci95"]
    clo, chi = cand_summary["der_live"]["ci95"]
    lat_b = base_summary["line_first_label_median_s"]["value"]
    lat_c = cand_summary["line_first_label_median_s"]["value"]
    return Verdict(der_ci_overlaps=clo <= bhi and chi >= blo, latency_within_10pct=lat_c <= 1.10 * lat_b + 1e-12)


def _scores(a, model: str, sp) -> list:
    found = collect(Path(a.results), model)
    out = []
    for r in sp.test:
        sp.require_test(r)
        if r not in found or 1 not in found[r]:
            raise SystemExit(f"{model}: no repeat 1 for {r}: compare only complete runs")
        ref, uem, ph = reference(r, Path(a.rttm_dir), Path(a.uem_dir))
        out.append(score_recording(load_result(found[r][1]), ref, ph, uem))
    return out


def run(a) -> dict:
    sp = splitmod.load(set_name=a.set)
    base, cand = _scores(a, a.base, sp), _scores(a, a.model, sp)
    sb, sc = summary(base), summary(cand)
    v = ship_rule(sb, sc)
    diffs = {}
    for key, stat in (("der_live", lambda x: pooled(x, "live")), ("der_bare", lambda x: pooled(x, "bare")),
                      ("line_first_label_median_s", line_delay(0.5)), ("monologue_split_rate", split_rate)):
        val, lo, hi = paired_bootstrap(base, cand, stat)
        diffs[key] = {"value": val, "ci95": [lo, hi]}
    return {"set": a.set, "base": a.base, "model": a.model, "base_summary": sb, "model_summary": sc,
            "paired_diff": diffs, "verdict": {"der_ci_overlaps": v.der_ci_overlaps,
                                              "latency_within_10pct": v.latency_within_10pct, "passes": v.passes}}


def markdown(s: dict) -> str:
    b, c, d, v = s["base_summary"], s["model_summary"], s["paired_diff"], s["verdict"]
    pct = lambda x: f"{x['value']:.1%} ({x['ci95'][0]:.1%}–{x['ci95'][1]:.1%})"            # noqa: E731
    pts = lambda x: f"{x['value'] * 100:+.2f} ({x['ci95'][0] * 100:+.2f} to {x['ci95'][1] * 100:+.2f}) pts"  # noqa: E731
    sec = lambda x: f"{x['value']:.2f} s ({x['ci95'][0]:.2f}–{x['ci95'][1]:.2f})"           # noqa: E731
    yes = lambda t: "yes" if t else "**no**"                                                # noqa: E731
    lat_b, lat_c = b["line_first_label_median_s"]["value"], c["line_first_label_median_s"]["value"]
    return "\n".join([
        f"| {s['set']} | {s['base']} | {s['model']} | {s['model']} − {s['base']} (paired) |", "|---|---|---|---|",
        f"| DER on screen | {pct(b['der_live'])} | {pct(c['der_live'])} | {pts(d['der_live'])} |",
        f"| DER, bare model | {pct(b['der_bare'])} | {pct(c['der_bare'])} | {pts(d['der_bare'])} |",
        f"| Line first label, median | {sec(b['line_first_label_median_s'])} | {sec(c['line_first_label_median_s'])} "
        f"| {d['line_first_label_median_s']['value']:+.3f} s |",
        f"| Monologues split | {pct(b['monologue_split_rate'])} | {pct(c['monologue_split_rate'])} "
        f"| {pts(d['monologue_split_rate'])} |",
        f"| Speed, peak memory | {b['speed_x_realtime']:.0f}x, {b['peak_mb']['median']:.0f} MB "
        f"| {c['speed_x_realtime']:.0f}x, {c['peak_mb']['median']:.0f} MB | |",
        "",
        f"Ship rule on {s['set']}: DER CI overlaps fp16's: {yes(v['der_ci_overlaps'])}; first label within 10% "
        f"({lat_c:.3f} s vs limit {1.1 * lat_b:.3f} s): {yes(v['latency_within_10pct'])}. "
        f"**{'Passes' if v['passes'] else 'Fails'}** on this set.", ""])


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="speaker_eval.compare")
    for k in ("--set", "--base", "--model", "--rttm-dir", "--uem-dir", "--results"):
        ap.add_argument(k, required=k not in ("--set", "--base"))
    ap.set_defaults(set="ami", base="fp16")
    ap.add_argument("--out-json")
    ap.add_argument("--out-md")
    a = ap.parse_args(argv)
    s = run(a)
    if a.out_json:
        Path(a.out_json).write_text(json.dumps(s, indent=2))
    md = markdown(s)
    if a.out_md:
        Path(a.out_md).write_text(md)
    print(md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
