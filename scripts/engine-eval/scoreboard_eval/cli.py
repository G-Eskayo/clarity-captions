"""Command-line interface for scoreboard evaluation."""
import argparse
import sys
from pathlib import Path
from typing import List

from .extract_english import extract_english
from .extract_languages import extract_languages
from .extract_hebrew import extract_hebrew
from .extract_translation import extract_translation
from .build import build_scoreboard
from .render import render_markdown, render_json
from .rows import ScoreboardSourceMissing


def build_command(args: argparse.Namespace) -> None:
    """Build scoreboard by extracting and rendering results.

    Args:
        args: Parsed command-line arguments
    """
    base_path = Path(args.perf_dir)

    # Load source files
    eng_file = base_path / "engine-accuracy-comparison.md"
    lang_file = base_path / "language-accuracy-comparison.md"
    heb_acc_file = base_path / "hebrew-accuracy-comparison.md"
    heb_core_file = base_path / "hebrew-coreml-comparison.md"
    trans_file = base_path / "translation-languages-results.json"

    if not eng_file.exists():
        raise FileNotFoundError(f"Missing {eng_file}")

    # Extract from all sources
    rows = []
    gaps = []

    # English accuracy
    print(f"Extracting from {eng_file.name}...", file=sys.stderr)
    try:
        with open(eng_file) as f:
            rows.extend(extract_english(f.read()))
    except ScoreboardSourceMissing as e:
        print(f"Warning: Skipping {eng_file.name}: {e}", file=sys.stderr)
        gaps.append(f"Missing data in {eng_file.name}: {e}")

    # Language accuracy
    if lang_file.exists():
        print(f"Extracting from {lang_file.name}...", file=sys.stderr)
        try:
            with open(lang_file) as f:
                rows.extend(extract_languages(f.read()))
        except ScoreboardSourceMissing as e:
            print(f"Warning: Skipping {lang_file.name}: {e}", file=sys.stderr)
            gaps.append(f"Missing data in {lang_file.name}: {e}")

    # Hebrew accuracy
    if heb_acc_file.exists() and heb_core_file.exists():
        print(f"Extracting from {heb_acc_file.name} and {heb_core_file.name}...", file=sys.stderr)
        try:
            with open(heb_acc_file) as f:
                acc_content = f.read()
            with open(heb_core_file) as f:
                core_content = f.read()
            rows.extend(extract_hebrew(acc_content, core_content))
        except ScoreboardSourceMissing as e:
            print(f"Warning: Skipping Hebrew files: {e}", file=sys.stderr)
            gaps.append(f"Missing data in Hebrew files: {e}")

    # Translation
    if trans_file.exists():
        print(f"Extracting from {trans_file.name}...", file=sys.stderr)
        try:
            with open(trans_file) as f:
                rows.extend(extract_translation(f.read()))
        except ScoreboardSourceMissing as e:
            print(f"Warning: Skipping {trans_file.name}: {e}", file=sys.stderr)
            gaps.append(f"Missing data in {trans_file.name}: {e}")

    print(f"Extracted {len(rows)} rows", file=sys.stderr)

    # Build scoreboard
    print("Building scoreboard...", file=sys.stderr)
    scoreboard = build_scoreboard(rows, dedup_engine_identity=True)

    # Add gaps from extraction errors
    if gaps:
        scoreboard.gaps.extend(gaps)
        scoreboard.gaps = sorted(list(set(scoreboard.gaps)))

    # Render outputs
    print("Rendering outputs...", file=sys.stderr)
    md_output = render_markdown(scoreboard)
    json_output = render_json(scoreboard)

    # Write outputs
    md_path = args.output_markdown
    json_path = args.output_json

    if md_path:
        with open(md_path, 'w') as f:
            f.write(md_output)
        print(f"Wrote {md_path}", file=sys.stderr)

    if json_path:
        with open(json_path, 'w') as f:
            f.write(json_output)
        print(f"Wrote {json_path}", file=sys.stderr)


def main(argv: List[str] = None) -> int:
    """Main entry point for CLI.

    Args:
        argv: Command-line arguments (defaults to sys.argv[1:])

    Returns:
        Exit code (0 for success, 1 for error)
    """
    parser = argparse.ArgumentParser(
        description="Build and render an engine scoreboard from evaluation results"
    )

    subparsers = parser.add_subparsers(dest='command', help='Commands')

    # build subcommand
    build_parser = subparsers.add_parser('build', help='Build scoreboard from source files')
    build_parser.add_argument(
        '--perf-dir',
        default='docs/perf',
        help='Directory containing performance result files (default: docs/perf)'
    )
    build_parser.add_argument(
        '--output-markdown',
        default='docs/perf/engine-scoreboard.md',
        help='Output markdown file (default: docs/perf/engine-scoreboard.md)'
    )
    build_parser.add_argument(
        '--output-json',
        default='docs/perf/engine-scoreboard.json',
        help='Output JSON file (default: docs/perf/engine-scoreboard.json)'
    )

    args = parser.parse_args(argv)

    if not args.command:
        parser.print_help()
        return 1

    try:
        if args.command == 'build':
            build_command(args)
            return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == '__main__':
    sys.exit(main())
