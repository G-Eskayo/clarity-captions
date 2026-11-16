#!/usr/bin/env python3
"""Generate engine scoreboard from live docs/perf files."""
import sys
from pathlib import Path

# Add engine-eval to path
sys.path.insert(0, str(Path(__file__).parent))

from scoreboard.cli import main

if __name__ == "__main__":
	# Generate against live docs/perf
	docs_root = Path(__file__).parent.parent.parent / "docs" / "perf"
	out_md = Path(__file__).parent.parent.parent / "docs" / "perf" / "engine-scoreboard.md"
	out_json = Path(__file__).parent.parent.parent / "docs" / "perf" / "engine-scoreboard.json"

	print(f"Generating scoreboard from: {docs_root}")
	print(f"Output markdown: {out_md}")
	print(f"Output JSON: {out_json}")

	argv = [
		"build",
		"--root", str(docs_root),
		"--out", str(out_md),
		"--json-out", str(out_json),
	]

	result = main(argv)
	sys.exit(result)
