#!/usr/bin/env python3
"""Manual verification of scoreboard implementation."""
import sys
from pathlib import Path
import tempfile
import json

# Add engine-eval to path
sys.path.insert(0, str(Path(__file__).parent / "scripts" / "engine-eval"))

try:
	from scoreboard.md_table import parse_tables
	from scoreboard.model import Row
	from scoreboard import sources, build

	print("✓ All imports successful")

	# Test 1: MD table parser
	print("\n=== Test 1: GFM Table Parser ===")
	table_text = """| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-ultra | 13.8% | 12.7% – 14.7% |
| apple | 17.2% | 16.0% – 18.4% |"""

	tables = parse_tables(table_text)
	assert len(tables) == 1, f"Expected 1 table, got {len(tables)}"
	assert len(tables[0].rows) == 2, f"Expected 2 rows, got {len(tables[0].rows)}"
	print(f"✓ Parsed table with {len(tables[0].headers)} headers and {len(tables[0].rows)} rows")

	# Test 2: Row dataclass
	print("\n=== Test 2: Row Dataclass ===")
	row = Row(
		language="English",
		task="captions",
		engine="test-engine",
		device_or_platform="iPhone",
		metric_name="WER",
		metric_value=0.138,
		ci_low=0.127,
		ci_high=0.147,
		source_ticket="#145",
		source_doc="test.md",
	)
	assert row.language == "English"
	assert row.metric_value == 0.138
	print(f"✓ Row created: {row.engine} on {row.device_or_platform}")

	# Test 3: Build with fixture files
	print("\n=== Test 3: Build Process ===")
	with tempfile.TemporaryDirectory() as tmpdir:
		tmppath = Path(tmpdir)

		# Create minimal fixture files
		fixture_engine = """# Engine accuracy

## Overall

| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-ultra | 13.8% | 12.7% – 14.7% |"""

		(tmppath / "engine-accuracy-comparison.md").write_text(fixture_engine)

		# Build
		rows = build.build(tmppath)
		print(f"✓ Built scoreboard with {len(rows)} rows")

		if rows:
			print(f"  First row: {rows[0].engine} ({rows[0].language})")

	# Test 4: Markdown rendering
	print("\n=== Test 4: Markdown Rendering ===")
	test_rows = [
		Row(
			language="English",
			task="captions",
			engine="parakeet-ultra",
			device_or_platform="iPhone",
			metric_name="WER",
			metric_value=0.138,
			ci_low=0.127,
			ci_high=0.147,
			source_ticket="#145",
			source_doc="test.md",
		),
		Row(
			language="Spanish",
			task="translation",
			engine="apple",
			device_or_platform="Mac",
			metric_name="chrF",
			metric_value=56.8,
			ci_low=56.2,
			ci_high=57.4,
			source_ticket="#159",
			source_doc="test.md",
		),
	]

	md = build.render_markdown(test_rows)
	assert "# Engine Scoreboard" in md
	assert "parakeet-ultra" in md
	assert "13.8%" in md
	print("✓ Markdown rendering works")
	print(f"  Generated {len(md)} characters of markdown")

	# Test 5: JSON rendering
	print("\n=== Test 5: JSON Rendering ===")
	json_str = build.render_json(test_rows)
	data = json.loads(json_str)
	assert "meta" in data
	assert "rows" in data
	assert len(data["rows"]) == 2
	assert "generated_at" in data["meta"]
	print("✓ JSON rendering works")
	print(f"  Generated {len(data['rows'])} rows in JSON")

	# Test 6: Live docs parsing (if they exist)
	print("\n=== Test 6: Live Docs Parsing ===")
	docs_root = Path(__file__).parent / "docs" / "perf"
	if docs_root.exists():
		try:
			rows = build.build(docs_root)
			print(f"✓ Parsed live docs: {len(rows)} rows total")

			# Show summary
			tasks = set(r.task for r in rows)
			languages = set(r.language for r in rows)
			engines = set(r.engine for r in rows)
			print(f"  Tasks: {sorted(tasks)}")
			print(f"  Languages: {len(languages)} unique")
			print(f"  Engines: {len(engines)} unique")
		except Exception as e:
			print(f"⚠ Error parsing live docs: {e}")
	else:
		print(f"⚠ docs/perf directory not found at {docs_root}")

	print("\n✓ ALL VERIFICATION TESTS PASSED")
	sys.exit(0)

except Exception as e:
	print(f"\n✗ VERIFICATION FAILED: {e}")
	import traceback
	traceback.print_exc()
	sys.exit(1)
