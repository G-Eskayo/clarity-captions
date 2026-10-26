"""Command line for the engine accuracy test (#145) and the language test (#158). Run as `python -m edacc_eval.cli <command>`."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="edacc_eval")
    sub = p.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build-shards", help="cut the corpus into accent-stratified shards")
    b.add_argument("--corpus", type=Path, required=True, help="directory with the EdAcc *.parquet files")
    b.add_argument("--out", type=Path, required=True)
    b.add_argument("--target-hours", type=float, default=1.0)

    fl = sub.add_parser("fleurs-shards", help="cut FLEURS test splits into per-language shards (#158)")
    fl.add_argument("--corpus", type=Path, required=True, help="directory with <config>/test.tsv and test.tar.gz")
    fl.add_argument("--out", type=Path, required=True)
    fl.add_argument("--languages", default="es,fr,de")
    fl.add_argument("--target-hours", type=float, default=1.0)

    s = sub.add_parser("sherpa", help="run sherpa-onnx over one shard, appending result lines")
    s.add_argument("--shard-dir", type=Path, required=True)
    s.add_argument("--results", type=Path, required=True)
    s.add_argument("--model-dir", type=Path, required=True)
    s.add_argument("--repeats", type=int, default=1)
    s.add_argument("--threads", type=int, default=4)
    s.add_argument("--status", type=Path)

    r = sub.add_parser("report", help="score every result so far and write the markdown report")
    r.add_argument("--shards", type=Path, required=True, help="directory with index.json and shard-NNN/")
    r.add_argument("--results", type=Path, required=True, help="directory of *.jsonl result files")
    r.add_argument("--out", type=Path, required=True)
    r.add_argument("--json-out", type=Path)

    rl = sub.add_parser("report-languages", help="score FLEURS results per language and write the #158 report")
    rl.add_argument("--shards", type=Path, required=True, help="directory with <lang>/index.json and shards")
    rl.add_argument("--results", type=Path, required=True)
    rl.add_argument("--out", type=Path, required=True)
    rl.add_argument("--json-out", type=Path)

    c = sub.add_parser("claim", help="atomically claim the next sherpa-onnx shard; prints its number or nothing")
    c.add_argument("--root", type=Path, required=True)
    c.add_argument("--total", type=int, required=True)
    c.add_argument("--host", required=True)
    c.add_argument("--first", type=int, default=1)
    d = sub.add_parser("claim-done", help="mark a claimed shard finished")
    d.add_argument("--root", type=Path, required=True)
    d.add_argument("--shard", type=int, required=True)

    m = sub.add_parser("compare", help="identical-text check for one engine across two result files")
    m.add_argument("a", type=Path)
    m.add_argument("b", type=Path)
    m.add_argument("--engine", default="sherpa-onnx")

    sl = sub.add_parser("sherpa-latency", help="growing-window live-latency lines for sherpa-onnx on one shard")
    sl.add_argument("--shard-dir", type=Path, required=True)
    sl.add_argument("--out", type=Path, required=True)
    sl.add_argument("--model-dir", type=Path, required=True)
    sl.add_argument("--threads", type=int, default=8)
    sl.add_argument("--hop", type=float, default=0.5)
    sl.add_argument("--max-clip-seconds", type=float, default=30.0)

    z = sub.add_parser("sizes", help="record a model folder's on-disk and zipped size into sizes.json")
    z.add_argument("--out", type=Path, required=True)
    z.add_argument("--model", required=True)
    z.add_argument("--folder", type=Path, required=True)
    z.add_argument("--include", default="", help="comma list of components inside the folder (default: all)")
    z.add_argument("--method", default="as published")
    z.add_argument("--license", default="CC BY 4.0")

    a = p.parse_args(argv)
    if a.cmd == "build-shards":
        from .shards import build_shards
        print(json.dumps(build_shards(a.corpus, a.out, a.target_hours), indent=2))
    elif a.cmd == "fleurs-shards":
        from .fleurs import build_fleurs_shards
        print(json.dumps(build_fleurs_shards(a.corpus, a.out, a.languages.split(","), a.target_hours), indent=2))
    elif a.cmd == "report-languages":
        from .report import write_language_report
        for lang, res in write_language_report(a.shards, a.results, a.out, a.json_out).items():
            print(f"{lang}: {res.verdict.verdict} ({res.score.clips_compared} clips compared)")
    elif a.cmd == "sherpa":
        from .sherpa_run import run_shard
        run_shard(a.shard_dir, a.results, a.model_dir, a.repeats, a.threads, a.status)
    elif a.cmd == "report":
        from .report import write_report
        write_report(a.shards, a.results, a.out, a.json_out)
    elif a.cmd == "claim":
        from .claims import claim_next
        k = claim_next(a.root, a.total, a.host, a.first)
        if k is not None:
            print(k)
    elif a.cmd == "claim-done":
        from .claims import mark_done
        mark_done(a.root, a.shard)
    elif a.cmd == "sherpa-latency":
        from .sherpa_run import run_latency
        print(f"sherpa latency clips run: {run_latency(a.shard_dir, a.out, a.model_dir, a.threads, a.hop, a.max_clip_seconds)}")
    elif a.cmd == "sizes":
        from .sizes import record
        inc = [x for x in a.include.split(",") if x] or None
        print(json.dumps(record(a.out, a.model, a.folder, a.method, a.license, include=inc)))
    elif a.cmd == "compare":
        from .results import compare_hypotheses
        print(json.dumps(compare_hypotheses([a.a], [a.b], a.engine), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
