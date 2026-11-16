"""Tests for the CLI (cli.py)."""
import pytest
from pathlib import Path
import tempfile
import json

from scoreboard import cli


class TestCLIBuildCommand:
	"""Test the 'build' subcommand."""

	def test_build_requires_root(self):
		"""Build command requires --root argument."""
		result = cli.main(["build", "--out", "/tmp/out.md"])
		assert result == 1

	def test_build_requires_out(self):
		"""Build command requires --out argument."""
		with tempfile.TemporaryDirectory() as tmpdir:
			result = cli.main(["build", "--root", tmpdir])
			assert result == 1

	def test_build_rejects_nonexistent_root(self):
		"""Build command rejects --root that isn't a directory."""
		with tempfile.TemporaryDirectory() as tmpdir:
			nonexistent = Path(tmpdir) / "does_not_exist"
			out = Path(tmpdir) / "out.md"

			result = cli.main(["build", "--root", str(nonexistent), "--out", str(out)])
			assert result == 1

	def test_build_creates_markdown_output(self):
		"""Build command creates markdown output file."""
		with tempfile.TemporaryDirectory() as tmpdir:
			root = Path(tmpdir)
			out = root / "out.md"

			result = cli.main(["build", "--root", str(root), "--out", str(out)])
			assert result == 0
			assert out.exists()

			content = out.read_text()
			assert "# Engine Scoreboard" in content or "No data yet" in content

	def test_build_with_json_output(self):
		"""Build command creates optional JSON output."""
		with tempfile.TemporaryDirectory() as tmpdir:
			root = Path(tmpdir)
			out = root / "out.md"
			json_out = root / "out.json"

			result = cli.main(["build", "--root", str(root), "--out", str(out), "--json-out", str(json_out)])
			assert result == 0
			assert out.exists()
			assert json_out.exists()

			# Verify JSON is valid
			data = json.loads(json_out.read_text())
			assert "meta" in data
			assert "rows" in data

	def test_build_with_fixture_files(self):
		"""Build command parses fixture files correctly."""
		with tempfile.TemporaryDirectory() as tmpdir:
			root = Path(tmpdir)

			# Create a simple fixture
			fixture = """# Engine accuracy

## Overall

| Engine | WER | 95% CI |
|---|---:|---|
| parakeet-ultra | 13.8% | 12.7% – 14.7% |"""

			(root / "engine-accuracy-comparison.md").write_text(fixture)

			out = root / "out.md"
			json_out = root / "out.json"

			result = cli.main(["build", "--root", str(root), "--out", str(out), "--json-out", str(json_out)])
			assert result == 0

			# Check markdown output has the data
			md = out.read_text()
			assert "parakeet-ultra" in md

			# Check JSON output has the data
			data = json.loads(json_out.read_text())
			assert len(data["rows"]) > 0
			assert data["rows"][0]["engine"] == "parakeet-ultra"


class TestCLIErrorHandling:
	"""Test error handling in CLI."""

	def test_malformed_markdown_doesnt_crash(self):
		"""Malformed markdown in sources doesn't crash the builder."""
		with tempfile.TemporaryDirectory() as tmpdir:
			root = Path(tmpdir)

			# Write malformed markdown that will cause parsing to fail gracefully
			(root / "engine-accuracy-comparison.md").write_text("invalid markdown\nno tables here")

			out = root / "out.md"
			result = cli.main(["build", "--root", str(root), "--out", str(out)])

			# Should complete successfully (all sources are optional)
			assert result == 0
			assert out.exists()


class TestCLISubcommands:
	"""Test that only 'build' subcommand is available."""

	def test_build_is_required_subcommand(self):
		"""CLI requires a subcommand."""
		result = cli.main([])
		# argparse exits with 2 for missing required argument
		assert result != 0

	def test_invalid_subcommand_fails(self):
		"""Invalid subcommand fails."""
		with tempfile.TemporaryDirectory() as tmpdir:
			result = cli.main(["invalid", "--root", tmpdir])
			assert result != 0
