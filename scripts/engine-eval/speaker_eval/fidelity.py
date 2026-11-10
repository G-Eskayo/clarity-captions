"""Choose one compressed Sortformer build per bit width, on calibration audio only (#271 step 2).

Rule, fixed before any build was run (docs/perf/speaker-scoreboard.md, step 2):
- every candidate and the shipped fp16 replay the same calibration recordings through the app's speaker path;
- a candidate's **drift** is the DER of its bare segments measured against fp16's segments on the same audio (pooled
  over recordings, 10 ms frames, best label mapping): what the compression changed, nothing else. The segments are
  deterministic (#275 is in the labels, not the segments);
- per bit width, the lowest drift goes on to the test sets; a tie goes to the smaller build;
- no choice on partial data. Bare DER against the dev reference is reported beside it, not used to choose.

  python -m speaker_eval.fidelity --results DIR --base fp16 --candidates pal8:8,pal8g:8,int8:8,pal6:6,pal6g:6 \
      --set ami --rttm-dir DIR --uem-dir DIR [--builds-dir DIR] --out-json F --out-md F
Results are DIR/<recording>.<label>.json (engine-eval speakers with an empty line list).
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path

from . import split as splitmod
from .der import ZERO, DerCounts, der
from .reference import clip, read_rttm, read_uem


class IncompleteCalibration(ValueError):
    pass


@dataclass
class Candidate:
    label: str
    bits: int
    drift: float
    mb: float = float("nan")
    recordings: int = 0
    bare_der_dev: float = float("nan")


def drift(base, cand, length: float) -> DerCounts:
    """DER of `cand` against `base` (both (speaker, start, end)) over the whole recording."""
    return der(base, cand, (0.0, length))


def parse_candidates(text: str) -> list:
    out = []
    for part in text.split(","):
        label, sep, bits = part.partition(":")
        if not sep or not bits.isdigit():
            raise ValueError(f"candidate {part!r}: expected label:bits")
        out.append((label.strip(), int(bits)))
    return out


def choose(cands: list, expected_recordings: int | None = None) -> dict:
    if expected_recordings is not None:
        short = [c.label for c in cands if c.recordings != expected_recordings]
        if short:
            raise IncompleteCalibration(f"not every calibration recording ran for {short}")
    best: dict = {}
    for c in sorted(cands, key=lambda c: (c.bits, c.drift, c.mb)):
        best.setdefault(c.bits, c.label)
    return best


def _segs(result: dict) -> list:
    return [(s["speaker"], s["start"], s["end"]) for s in result["segments"]]


def run(a) -> dict:
    sp = splitmod.load(set_name=a.set)
    results = Path(a.results)
    cands = parse_candidates(a.candidates)
    recs = sorted({p.name.split(".")[0] for p in results.glob(f"*.{a.base}.json")})
    for r in recs:
        sp.require_calibration(r)                # refuse a test recording before reading anything else
    if not recs:
        raise IncompleteCalibration(f"no {a.base} results in {results}")
    rttm = {}
    for r in recs:
        f = Path(a.rttm_dir) / f"{r}.rttm"
        rttm[r] = read_rttm(f).get(r, []) if f.exists() else None
    uems = {r: read_uem(Path(a.uem_dir) / f"{r}.uem").get(r) if (Path(a.uem_dir) / f"{r}.uem").exists() else None
            for r in recs}
    base = {r: json.loads((results / f"{r}.{a.base}.json").read_text()) for r in recs}
    out = []
    per_rec: dict = {}
    for label, bits in cands:
        total, bare_total, n = ZERO, ZERO, 0
        mb = float("nan")
        for r in recs:
            p = results / f"{r}.{label}.json"
            if not p.exists():
                continue
            res = json.loads(p.read_text())
            d = drift(_segs(base[r]), _segs(res), float(base[r]["audio_seconds"]))
            total, n = total + d, n + 1
            per_rec.setdefault(r, {})[label] = d.der
            if rttm[r] is not None and uems[r] is not None:
                ref = [(s.speaker, s.start, s.end) for s in clip(rttm[r], uems[r])]
                bare_total = bare_total + der(ref, _segs(res), uems[r])
        if a.builds_dir and (Path(a.builds_dir) / label / "build.json").exists():
            mb = json.loads((Path(a.builds_dir) / label / "build.json").read_text())["compiled_mb"]
        out.append(Candidate(label, bits, total.der, mb, n, bare_total.der))
    base_bare = ZERO
    for r in recs:
        if rttm[r] is not None and uems[r] is not None:
            ref = [(s.speaker, s.start, s.end) for s in clip(rttm[r], uems[r])]
            base_bare = base_bare + der(ref, _segs(base[r]), uems[r])
    chosen = choose(out, expected_recordings=len(recs))
    return {"set": a.set, "base": a.base, "recordings": recs, "base_bare_der_dev": base_bare.der,
            "candidates": [c.__dict__ for c in out], "per_recording_drift": per_rec, "chosen": chosen}


def markdown(s: dict) -> str:
    lines = [f"Calibration ({s['set']}, {len(s['recordings'])} recordings: {', '.join(s['recordings'])}), base "
             f"{s['base']} (bare DER vs dev reference {s['base_bare_der_dev']:.1%}).", "",
             "| Build | Bits | Drift from fp16 | Bare DER vs dev reference | Chosen |", "|---|---|---|---|---|"]
    for c in sorted(s["candidates"], key=lambda c: (-c["bits"], c["drift"])):
        mark = "**yes**" if s["chosen"].get(c["bits"]) == c["label"] else ""
        lines.append(f"| {c['label']} | {c['bits']} | {c['drift']:.2%} | {c['bare_der_dev']:.1%} | {mark} |")
    return "\n".join(lines) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="speaker_eval.fidelity")
    ap.add_argument("--results", required=True)
    ap.add_argument("--base", default="fp16")
    ap.add_argument("--candidates", required=True)
    ap.add_argument("--set", default="ami")
    ap.add_argument("--rttm-dir", required=True)
    ap.add_argument("--uem-dir", required=True)
    ap.add_argument("--builds-dir", help="DIR/<label>/build.json gives each build's compiled size (ties)")
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
