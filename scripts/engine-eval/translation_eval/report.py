"""Score translation results per language pair and write the markdown report (#159).

Same shape as edacc_eval.report: rebuilt from every result file each time; only segments every engine finished
are compared; repeat 1 is the scored run.
"""
from __future__ import annotations

from collections import defaultdict
from typing import Iterable

from .score import N_BOOT, bootstrap_mean, chrf_bootstrap, paired_chrf_diff, segment_stats, speed_summary

SPEED_SET = "edacc-lines"
SET_ORDER = ["flores", "flores-caption", "speech", "speech-caption", "edacc-lines"]
SET_LABEL = {
    "flores": "FLORES-200 devtest, as written",
    "flores-caption": "FLORES-200 devtest, caption-style",
    "speech": "WMT24++ speech transcripts, as written",
    "speech-caption": "WMT24++ speech transcripts, caption-style",
    "edacc-lines": "EdAcc caption lines (no reference)",
}


def _key(r: dict) -> tuple[str, str]:
    return str(r["engine"]), str(r["model"])


def common_ids(rows: Iterable[dict], ids: list[str]) -> list[str]:
    """Ids (in set order) that every engine/model present in `rows` finished on repeat 1."""
    done: dict[tuple[str, str], set[str]] = defaultdict(set)
    for r in rows:
        if int(r["repeat"]) == 1:
            done[_key(r)].add(r["clip_id"])
    if not done:
        return []
    shared = set.intersection(*done.values())
    return [i for i in ids if i in shared]


def line_checks(rows: list[dict], sources: dict[str, str]) -> dict:
    """Reference-free checks for one engine on caption lines: left untranslated, empty, identical across repeats."""
    by_rep: dict[int, dict[str, str]] = defaultdict(dict)
    for r in rows:
        if r["clip_id"] in sources:
            by_rep[int(r["repeat"])][r["clip_id"]] = r["hypothesis"]
    first = by_rep.get(1, {})
    norm = lambda s: " ".join(s.lower().split())  # noqa: E731
    out = {"lines": len(first),
           "untranslated": sum(1 for i, h in first.items() if h.strip() and norm(h) == norm(sources[i])),
           "empty": sum(1 for h in first.values() if not h.strip()),
           "identical_repeats": None}
    if 2 in by_rep:
        both = [i for i in first if i in by_rep[2]]
        if both:
            out["identical_repeats"] = sum(1 for i in both if first[i] == by_rep[2][i]) / len(both)
    return out


def score_pair(sets: dict[str, list[dict]], rows: list[dict], comet: dict, n_boot: int = N_BOOT,
               speed_rows: list[dict] | None = None) -> dict:
    """sets: set name -> set rows; rows: result lines for this pair; comet: (engine, model, id) -> segment score;
    speed_rows: caption-line results from an isolated timing pass, used instead of the main runs' timing."""
    out = {"sets": {}, "speed": []}
    by_set: dict[str, list[dict]] = defaultdict(list)
    set_of = {r["id"]: name for name, rs in sets.items() for r in rs}
    for r in rows:
        if r["clip_id"] in set_of:
            by_set[set_of[r["clip_id"]]].append(r)
    for name in [s for s in SET_ORDER if s in sets] + sorted(set(sets) - set(SET_ORDER)):
        srows = sets[name]
        if not srows or srows[0].get("reference") is None or not by_set.get(name):
            continue
        ids = common_ids(by_set[name], [r["id"] for r in srows])
        seg = {r["id"]: r for r in srows}
        groups = [seg[i]["group"] for i in ids]
        hyp: dict[tuple[str, str], dict[str, str]] = defaultdict(dict)
        for r in by_set[name]:
            if int(r["repeat"]) == 1:
                hyp[_key(r)][r["clip_id"]] = r["hypothesis"]
        engines = []
        for k in sorted(hyp):
            stats = [segment_stats(hyp[k][i], seg[i]["reference"]) for i in ids]
            point, lo, hi = chrf_bootstrap(stats, groups, n_boot=n_boot)
            cvals = [comet.get((k[0], k[1], i)) for i in ids]
            c = bootstrap_mean(cvals, groups, n_boot=n_boot) if ids and all(v is not None for v in cvals) else None
            engines.append({"engine": k[0], "model": k[1], "chrf": point, "ci": (lo, hi), "comet": c,
                            "_stats": stats})
        engines.sort(key=lambda e: -e["chrf"])
        for e in engines:
            e["diff_vs_best"] = paired_chrf_diff(e["_stats"], engines[0]["_stats"], groups, n_boot=n_boot) \
                if e is not engines[0] else None
        for e in engines:
            del e["_stats"]
        out["sets"][name] = {"n": len(ids), "groups": len(set(groups)), "engines": engines}
    if SPEED_SET in sets:
        sources = {r["id"]: r["source"] for r in sets[SPEED_SET]}
        per: dict[tuple[str, str], list[dict]] = defaultdict(list)
        for r in (speed_rows if speed_rows is not None else by_set.get(SPEED_SET, [])):
            if r["clip_id"] in sources:
                per[_key(r)].append(r)
        for k in sorted(per):
            rs = per[k]
            single = [float(r["processing_seconds"]) for r in sorted(rs, key=lambda r: int(r["repeat"]))
                      if int(r.get("batch_size", 1)) == 1]
            out["speed"].append({"engine": k[0], "model": k[1], "speed": speed_summary(single),
                                 "checks": line_checks(rs, sources),
                                 "words": sum(len(sources[r["clip_id"]].split()) for r in rs
                                              if int(r["repeat"]) == 1) / max(1, sum(1 for r in rs
                                                                                    if int(r["repeat"]) == 1))})
    return out


def _f(x: float, d: int = 1) -> str:
    return f"{x:.{d}f}"


def build_report(pairs: dict[str, dict], meta: dict) -> str:
    """pairs: pair -> score_pair output. meta: generated, sizes {model: row}, missing {engine: reason},
    delivery [rows], notes [lines]."""
    L = ["# Translation comparison: results (#159)", "",
         f"Generated {meta.get('generated', '')} by `python -m translation_eval.cli report`. Design and method: "
         "[`translation-comparison-design.md`](translation-comparison-design.md).", ""]
    for note in meta.get("notes", []):
        L += [note, ""]
    for engine, why in sorted(meta.get("missing", {}).items()):
        L.append(f"- **{engine}: not run.** {why}")
    if meta.get("missing"):
        L.append("")
    for pair, s in pairs.items():
        L += [f"## {pair}", ""]
        for name, cell in s["sets"].items():
            L += [f"### {SET_LABEL.get(name, name)}", "",
                  f"{cell['n']} segments in {cell['groups']} bootstrap groups, scored on the segments every engine "
                  "finished. chrF 0 to 100, higher is better; COMET (wmt22-comet-da) 0 to 1. Brackets: 95% CI. "
                  "\"vs best\": paired chrF difference to the top engine, with its 95% CI.", "",
                  "| Engine | Model | chrF | COMET | vs best |", "|---|---|---|---|---|"]
            for e in cell["engines"]:
                lo, hi = e["ci"]
                comet = (f"{e['comet'][0]:.3f} [{e['comet'][1]:.3f}–{e['comet'][2]:.3f}]" if e["comet"] else "–")
                d = e["diff_vs_best"]
                vs = "best" if d is None else f"{d[0]:+.1f} [{d[1]:+.1f} to {d[2]:+.1f}]"
                L.append(f"| {e['engine']} | {e['model']} | {_f(e['chrf'])} [{_f(lo)}–{_f(hi)}] | {comet} | {vs} |")
            L.append("")
        if s["speed"]:
            L += ["### Time per caption line and failure checks (EdAcc lines)", "",
                  "One line at a time (batch size 1), as live captions arrive; model load and the first 5 lines "
                  "excluded; all repeats pooled. Untranslated: output equals the input. Same text: share of lines "
                  "identical across repeats 1 and 2.", "",
                  "| Engine | Model | Lines | Median ms | p95 ms | Untranslated | Empty | Same text |",
                  "|---|---|---|---|---|---|---|---|"]
            for e in s["speed"]:
                sp, c = e["speed"], e["checks"]
                ident = "–" if c["identical_repeats"] is None else f"{100 * c['identical_repeats']:.1f}%"
                ms = (f"{sp['median_ms']:.0f} | {sp['p95_ms']:.0f}" if sp else "– | –")
                L.append(f"| {e['engine']} | {e['model']} | {c['lines']} | {ms} | {c['untranslated']} | "
                         f"{c['empty']} | {ident} |")
            L.append("")
    sizes = meta.get("sizes", {})
    if sizes:
        L += ["## Model size per language pair", "", "| Model | On disk | Zipped | How measured | Licence |",
              "|---|---|---|---|---|"]
        for m, r in sorted(sizes.items()):
            z = "–" if r.get("zipped_bytes") is None else f"{r['zipped_bytes'] / 1e6:.0f} MB"
            L.append(f"| {m} | {r['disk_bytes'] / 1e6:.0f} MB | {z} | {r['method']} | "
                     f"{r['license']} |")
        L.append("")
    if meta.get("delivery"):
        L += ["## How the language model gets onto the device", "", "| Engine | Who downloads | System UI | Notes |",
              "|---|---|---|---|"]
        L += [f"| {d['engine']} | {d['who']} | {d['ui']} | {d['notes']} |" for d in meta["delivery"]]
        L.append("")
    return "\n".join(L).rstrip() + "\n"
