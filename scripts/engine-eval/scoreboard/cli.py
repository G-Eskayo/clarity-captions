"""Command-line interface for scoreboard: build and render performance summaries.

Run as `python -m scoreboard.cli build --root <path> --out <output.md> [--json-out <output.json>]`.
"""
import argparse
import logging
import sys
from pathlib import Path

from . import build as build_module


logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


def main(argv: list[str] | None = None) -> int:
	p = argparse.ArgumentParser(prog="scoreboard")
	sub = p.add_subparsers(dest="cmd", required=True)

	b = sub.add_parser("build", help="aggregate source docs and render scoreboard")
	b.add_argument("--root", type=Path, required=True, help="root directory containing source markdown files (e.g. docs/perf/)")
	b.add_argument("--out", type=Path, required=True, help="output markdown file")
	b.add_argument("--json-out", type=Path, help="optional JSON output file")

	args = p.parse_args(argv)

	if args.cmd == "build":
		if not args.root.is_dir():
			print(f"error: --root must be a directory, got {args.root}", file=sys.stderr)
			return 1

		try:
			rows = build_module.build(args.root)
			md = build_module.render_markdown(rows)
			args.out.write_text(md)
			logger.info(f"Wrote {len(rows)} rows to {args.out}")

			if args.json_out:
				json_str = build_module.render_json(rows)
				args.json_out.write_text(json_str)
				logger.info(f"Wrote JSON to {args.json_out}")

			return 0
		except Exception as e:
			logger.error(f"Build failed: {e}", exc_info=True)
			return 1

	return 0


if __name__ == "__main__":
	sys.exit(main())
