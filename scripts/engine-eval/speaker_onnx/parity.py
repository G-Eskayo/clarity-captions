"""python -I -m speaker_onnx.parity <port result> <engine-eval result> --until S   (#160)

Checks the Python port against the app's own run on the same weights: the same caption requests at the same moments,
the same frame-level speaker activity (slots matched one-to-one), and the same labels on screen. Only the first
`--until` seconds are compared (an excerpt run stops there; segments near the cut are still tentative).
"""
from __future__ import annotations

import argparse
import itertools
import json
import sys

import numpy as np


def activity(segs, until, step=0.01, speakers=8):
    n = int(until / step)
    a = np.zeros((speakers, n), bool)
    for s in segs:
        lo, hi = int(round(s["start"] / step)), min(n, int(round(s["end"] / step)))
        if hi > lo:
            a[s["speaker"], lo:hi] = True
    return a


def compare(port: dict, app: dict, until: float) -> dict:
    keep = lambda r: [e for e in r["emissions"] if e["now"] <= until]
    pe, ae = keep(port), keep(app)
    sched = [(round(e["now"], 6), e["phrase"], e["final"]) for e in pe] == \
            [(round(e["now"], 6), e["phrase"], e["final"]) for e in ae]
    A, B = activity(port["segments"], until), activity(app["segments"], until)
    best, mapping = -1.0, None
    for perm in itertools.permutations(range(4)):
        frames = np.mean(np.all(A[list(perm)] == B[:4], axis=0))
        if frames > best:
            best, mapping = frames, perm
    speech = B[:4].any(axis=0)
    finals = lambda es: {e["phrase"]: e["label"] for e in es if e["final"]}
    pf, af = finals(pe), finals(ae)
    same = sum(1 for k in af if pf.get(k) == af[k])
    return {"until_s": until, "schedule_identical": sched, "requests": [len(pe), len(ae)],
            "frame_agreement_all": best, "slot_map_port_to_app": mapping,
            "frame_agreement_speech": float(np.mean(np.all(A[list(mapping)][:, speech] == B[:4][:, speech], axis=0))),
            "final_labels_same": f"{same}/{len(af)}"}


def main(argv=None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("port")
    p.add_argument("app")
    p.add_argument("--until", type=float, required=True)
    a = p.parse_args(argv)
    r = compare(json.load(open(a.port)), json.load(open(a.app)), a.until)
    print(json.dumps(r, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
