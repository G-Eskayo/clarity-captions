"""Command line for the engine accuracy test (#145). Run as `python -m edacc_eval.cli <command>`."""
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

    a = p.parse_args(argv)
    if a.cmd == "build-shards":
        from .shards import build_shards
        print(json.dumps(build_shards(a.corpus, a.out, a.target_hours), indent=2))
    elif a.cmd == "sherpa":
        from .sherpa_run import run_shard
        run_shard(a.shard_dir, a.results, a.model_dir, a.repeats, a.threads, a.status)
    elif a.cmd == "report":
        from .report import write_report
        write_report(a.shards, a.results, a.out, a.json_out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
