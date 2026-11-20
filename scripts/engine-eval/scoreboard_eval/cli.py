"""Command line for the engine scoreboard. Run as `python -m scoreboard_eval.cli <command>`."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="scoreboard_eval")
    sub = p.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build", help="aggregate all engine metrics into one scoreboard")
    b.add_argument("--perf-dir", type=Path, required=True, help="docs/perf directory")
    b.add_argument("--out", type=Path, required=True, help="output markdown file")
    b.add_argument("--json-out", type=Path, help="optional JSON output")

    a = p.parse_args(argv)
    if a.cmd == "build":
        from .report import write_scoreboard
        write_scoreboard(a.perf_dir, a.out, a.json_out)
        print(f"Wrote {a.out}")
        if a.json_out:
            print(f"Wrote {a.json_out}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
