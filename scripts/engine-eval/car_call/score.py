"""Score a car-call set (#303): one engine pass over the whole scene, word error rate charged to each voice.

The engine hears the call and the live talker in one clip, as the app would. Its hypothesis is aligned once
against both references in the order they're heard (far, then near: the scenes never overlap), using the same
minimum-edit alignment and normalizer as every other result in docs/testing/results. Each substitution and
deletion belongs to the voice whose reference word it hits; an inserted word belongs to the voice of the
reference word just before it (or just after, at the very start).

    python -m car_call.score --set ~/Library/Caches/seal-car-call/set --results R1.jsonl R2.jsonl \
        --out docs/testing/results/YYYY-MM-DD-car-call.md --json-out car-call.json
"""
from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

from edacc_eval.normalize import normalize
from edacc_eval.results import load_results
from edacc_eval.wer import Counts, align_pairs, bootstrap_ci

VOICES = ("far", "near")
CONDITION_ORDER = ["clean-far", "clean-near", "phone"]


def conversation(speaker: str) -> str:
    """EdAcc speaker ids are <conversation>-<side>: EDACC-C55-B -> EDACC-C55."""
    return speaker.rsplit("-", 1)[0]


def split_counts(far_reference: str, near_reference: str, hypothesis: str) -> dict[str, Counts]:
    far, near, hyp = normalize(far_reference).split(), normalize(near_reference).split(), normalize(hypothesis).split()
    ref = far + near
    owner = ["far"] * len(far) + ["near"] * len(near)
    tally = {v: {"sub": 0, "dele": 0, "ins": 0} for v in VOICES}
    pending_ins = 0  # insertions before the first reference word
    last: str | None = None
    for i, j in align_pairs(ref, hyp):
        if i is None:
            if last is None:
                pending_ins += 1
            else:
                tally[last]["ins"] += 1
            continue
        last = owner[i]
        if pending_ins:
            tally[last]["ins"] += pending_ins
            pending_ins = 0
        if j is None:
            tally[last]["dele"] += 1
        elif ref[i] != hyp[j]:
            tally[last]["sub"] += 1
    if pending_ins:  # empty reference: nothing to charge but the far voice
        tally["far"]["ins"] += pending_ins
    n = {"far": len(far), "near": len(near)}
    return {v: Counts(sub=t["sub"], dele=t["dele"], ins=t["ins"], n=n[v]) for v, t in tally.items()}


def _condition_key(c: str) -> tuple:
    if c in CONDITION_ORDER:
        return (0, CONDITION_ORDER.index(c), 0)
    if c.startswith("snr"):
        return (1, 0, -float(c[3:]))
    return (2, 0, 0)


def score(manifest: list[dict], results: list[dict]) -> dict:
    """{(model, condition): {voice: {wer, ci, errors, n, clips, sub, dele, ins}}}, pooled over clips and repeats;
    the 95% CI resamples source pairs (bootstrap), so one hard clip can't hide."""
    by_id = {m["clip_id"]: m for m in manifest}
    acc: dict = defaultdict(lambda: defaultdict(lambda: defaultdict(lambda: [0, 0, 0, 0, 0])))
    for r in results:
        m = by_id.get(r["clip_id"])
        if m is None:
            continue
        counts = split_counts(m["far_reference"], m["near_reference"], r.get("hypothesis") or "")
        group = m.get("pair") or m["clip_id"].rsplit("-", 1)[0]
        for v in VOICES:
            if counts[v].n == 0:
                continue
            a = acc[(r["model"], m["condition"])][v][group]
            c = counts[v]
            a[0] += c.errors; a[1] += c.n; a[2] += c.sub; a[3] += c.dele; a[4] += c.ins
    table: dict = {}
    for key, voices in acc.items():
        table[key] = {}
        for v, groups in voices.items():
            e = sum(g[0] for g in groups.values()); n = sum(g[1] for g in groups.values())
            lo, hi = bootstrap_ci({k: (g[0], g[1]) for k, g in groups.items()}, seed=303)
            table[key][v] = {"wer": e / n if n else float("nan"), "ci": [lo, hi], "errors": e, "n": n,
                             "clips": len(groups), "sub": sum(g[2] for g in groups.values()),
                             "dele": sum(g[3] for g in groups.values()), "ins": sum(g[4] for g in groups.values())}
    return table


def _cell(d: dict | None) -> str:
    if not d:
        return "–"
    return f"{100 * d['wer']:.1f}% ({100 * d['ci'][0]:.0f}–{100 * d['ci'][1]:.0f})"


def render(table: dict, models: list[str]) -> str:
    conditions = sorted({c for _, c in table}, key=_condition_key)
    head = "| Condition | " + " | ".join(f"{m} far | {m} near" for m in models) + " |"
    sep = "|---|" + "---|---|" * len(models)
    rows = []
    for c in conditions:
        cells = []
        for m in models:
            t = table.get((m, c), {})
            cells += [_cell(t.get("far")), _cell(t.get("near"))]
        rows.append(f"| {c} | " + " | ".join(cells) + " |")
    return "\n".join([head, sep, *rows])


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--set", type=Path, required=True, help="the generated set (manifest.jsonl)")
    p.add_argument("--results", type=Path, nargs="+", required=True)
    p.add_argument("--out", type=Path, help="markdown table")
    p.add_argument("--json-out", type=Path)
    a = p.parse_args(argv)
    manifest = [json.loads(l) for l in (a.set / "manifest.jsonl").read_text().splitlines() if l.strip()]
    results, stats = load_results(a.results)
    table = score(manifest, results)
    models = sorted({m for m, _ in table})
    md = render(table, models)
    print(md)
    print(f"\n{stats}")
    if a.out:
        a.out.write_text(md + "\n")
    if a.json_out:
        a.json_out.write_text(json.dumps({f"{m}|{c}": v for (m, c), v in table.items()}, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
