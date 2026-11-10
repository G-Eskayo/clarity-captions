"""python -m speaker_eval.cli phrases | score   (#271)

phrases: write the caption stream for every TEST recording (calibration recordings never get one).
score:   score every result for one model; refuses calibration recordings and incomplete runs.
Results are named <recording>.<model>.r<repeat>.json (engine-eval speakers --out).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from . import split as splitmod
from .reference import clip, phrases, read_rttm, read_uem
from .report import markdown
from .score import load_result, same_output, score_recording, summary

NAME = re.compile(r"^(?P<rec>[A-Za-z0-9]+)\.(?P<model>[A-Za-z0-9_\-]+)\.r(?P<rep>\d+)\.json$")


def reference(rec: str, rttm_dir: Path, uem_dir: Path):
    ref = read_rttm(rttm_dir / f"{rec}.rttm").get(rec, [])
    uem = read_uem(uem_dir / f"{rec}.uem").get(rec)
    if not ref or uem is None:
        raise SystemExit(f"no reference or UEM for {rec}")
    ref = clip(ref, uem)
    return ref, uem, phrases(ref)


def cmd_phrases(a) -> int:
    sp = splitmod.load(a.split, a.set)
    a.out.mkdir(parents=True, exist_ok=True)
    for rec in sp.test:
        sp.require_test(rec)
        _, _, ph = reference(rec, a.rttm_dir, a.uem_dir)
        (a.out / f"{rec}.phrases.json").write_text(json.dumps([{"start": p.start, "end": p.end} for p in ph]))
        print(f"{rec}: {len(ph)} lines")
    return 0


def collect(results: Path, model: str) -> dict[str, dict[int, Path]]:
    out: dict[str, dict[int, Path]] = {}
    for p in sorted(results.glob("*.json")):
        m = NAME.match(p.name)
        if m and m["model"] == model:
            out.setdefault(m["rec"], {})[int(m["rep"])] = p
    return out


def cmd_score(a) -> int:
    sp = splitmod.load(a.split, a.set)
    found = collect(a.results, a.model)
    for rec in found:
        sp.require_test(rec)                       # a calibration result here is a leak: stop, don't skip
    missing = [r for r in sp.test if r not in found or 1 not in found[r]]
    if missing and not a.partial:
        print(f"missing repeat 1 for {len(missing)} test recording(s): {', '.join(missing)}", file=sys.stderr)
        return 2
    recs, differ, repeated = [], [], 0
    for rec in sp.test:
        if rec not in found or 1 not in found[rec]:
            continue
        ref, uem, ph = reference(rec, a.rttm_dir, a.uem_dir)
        first = load_result(found[rec][1])
        recs.append(score_recording(first, ref, ph, uem))
        for rep, path in found[rec].items():
            if rep != 1:
                repeated += 1
                if not same_output(first, load_result(path)):
                    differ.append(f"{rec} r{rep}")
    s = summary(recs)
    s.update({"model": a.model, "set": a.set, "repeats_checked": repeated, "repeats_differing": differ,
              "missing": missing, "per_recording": [
                  {"recording": r.recording, "der_live": r.live.der, "der_bare": r.bare.der, "der_floor": r.floor.der,
                   "ref_speakers": r.ref_speakers, "shown_speakers": r.shown_speakers,
                   "monologues": len(r.monologues), "split": sum(1 for x, _ in r.monologues if x),
                   "audio_s": r.audio_s, "peak_mb": r.peak_mb} for r in recs]})
    if a.meta:
        s["meta"] = json.loads(Path(a.meta).read_text())
    a.out_json.parent.mkdir(parents=True, exist_ok=True)
    a.out_json.write_text(json.dumps(s, indent=1, sort_keys=True))
    a.out_md.write_text(markdown(s))
    print(f"{a.model}: live DER {s['der_live']['value']:.2%} "
          f"({s['der_live']['ci95'][0]:.2%}-{s['der_live']['ci95'][1]:.2%}) over {len(recs)} recordings")
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="speaker_eval")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("phrases", "score"):
        q = sub.add_parser(name)
        q.add_argument("--rttm-dir", type=Path, required=True)
        q.add_argument("--uem-dir", type=Path, required=True)
        q.add_argument("--split", type=Path, default=splitmod.DEFAULT)
        q.add_argument("--set", default="ami", help="which corpus in the split: ami or chime6")
    sub.choices["phrases"].add_argument("--out", type=Path, required=True)
    sc = sub.choices["score"]
    sc.add_argument("--results", type=Path, required=True)
    sc.add_argument("--model", required=True)
    sc.add_argument("--out-md", type=Path, required=True)
    sc.add_argument("--out-json", type=Path, required=True)
    sc.add_argument("--meta", help="JSON with model size, sha256, host: printed in the report")
    sc.add_argument("--partial", action="store_true", help="score what exists (progress checks only, never a decision)")
    a = p.parse_args(argv)
    return {"phrases": cmd_phrases, "score": cmd_score}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
