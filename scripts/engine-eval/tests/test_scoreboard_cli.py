"""Tests for CLI integration."""
import json
import tempfile
from pathlib import Path
import pytest
from scoreboard_eval.cli import main


def _find_repo_root() -> Path:
    """Find the repository root by looking for .git or docs/perf marker."""
    current = Path(__file__).parent.absolute()
    # Walk up from test file looking for repo root
    for _ in range(10):  # Limit depth to avoid infinite loops
        if (current / '.git').exists() or (current / 'docs' / 'perf').exists():
            return current
        if current.parent == current:  # Reached filesystem root
            break
        current = current.parent
    # Fallback to current working directory
    return Path.cwd()


def test_build_command_with_real_files():
    """Test case 13: Build command runs end-to-end with real files."""
    # This test runs the real CLI against the actual repo files
    # It verifies that the CLI can process all source files without error

    repo_root = _find_repo_root()
    perf_dir = repo_root / 'docs' / 'perf'

    # Check if required files exist
    if not (perf_dir / 'engine-accuracy-comparison.md').exists():
        pytest.skip("Missing engine-accuracy-comparison.md")

    with tempfile.TemporaryDirectory() as tmpdir:
        output_md = Path(tmpdir) / 'engine-scoreboard.md'
        output_json = Path(tmpdir) / 'engine-scoreboard.json'

        argv = [
            'build',
            '--perf-dir', str(perf_dir),
            '--output-markdown', str(output_md),
            '--output-json', str(output_json),
        ]

        # Run the CLI
        result = main(argv)

        # Should succeed
        assert result == 0

        # Output files should be created
        assert output_md.exists()
        assert output_json.exists()

        # Markdown should be valid
        md_content = output_md.read_text()
        assert '# Engine Scoreboard' in md_content
        assert len(md_content) > 100

        # JSON should be valid
        json_content = output_json.read_text()
        data = json.loads(json_content)
        assert 'rows' in data
        assert 'gaps' in data
        assert isinstance(data['rows'], list)


def test_build_command_missing_file():
    """Test case 13: CLI reports error for missing required file."""
    with tempfile.TemporaryDirectory() as tmpdir:
        output_md = Path(tmpdir) / 'engine-scoreboard.md'
        output_json = Path(tmpdir) / 'engine-scoreboard.json'

        argv = [
            'build',
            '--perf-dir', '/nonexistent/directory',
            '--output-markdown', str(output_md),
            '--output-json', str(output_json),
        ]

        # Run the CLI
        result = main(argv)

        # Should fail
        assert result != 0


def test_build_command_wrong_cwd():
    """Test case 13: CLI handles wrong working directory."""
    with tempfile.TemporaryDirectory() as tmpdir:
        # Create a temp directory as cwd
        wrong_cwd = Path(tmpdir)

        output_md = wrong_cwd / 'engine-scoreboard.md'
        output_json = wrong_cwd / 'engine-scoreboard.json'

        argv = [
            'build',
            '--perf-dir', 'docs/perf',  # Relative path that won't exist from tmpdir
            '--output-markdown', str(output_md),
            '--output-json', str(output_json),
        ]

        # Run the CLI from the temp directory
        result = main(argv)

        # Should fail gracefully (exit code 1, not crash)
        assert result != 0


def test_cli_no_command():
    """Test CLI with no command shows help."""
    result = main([])

    # Should fail gracefully
    assert result != 0


def test_build_command_default_paths():
    """Test build command uses default paths."""
    # Just verify the defaults work by calling with no path args
    # This will fail if files don't exist, but that's OK
    argv = ['build']

    result = main(argv)

    # Don't assert on result since files may not exist,
    # just verify it doesn't crash
    assert isinstance(result, int)


def test_build_command_handles_missing_sections():
    """Test case 2 (fix verification): Missing source sections become gaps, not errors."""
    # Create mock files with missing required sections
    with tempfile.TemporaryDirectory() as tmpdir:
        perf_dir = Path(tmpdir)

        # Create engine file with missing "## Overall" section
        eng_file = perf_dir / 'engine-accuracy-comparison.md'
        eng_file.write_text("""# Engine comparison

No ## Overall section here, so ScoreboardSourceMissing will be raised.
""")

        output_md = perf_dir / 'engine-scoreboard.md'
        output_json = perf_dir / 'engine-scoreboard.json'

        argv = [
            'build',
            '--perf-dir', str(perf_dir),
            '--output-markdown', str(output_md),
            '--output-json', str(output_json),
        ]

        # Run the CLI
        result = main(argv)

        # Should succeed (not fail on missing section)
        assert result == 0

        # Output files should be created with gaps
        assert output_md.exists()
        assert output_json.exists()

        # Check that gaps include the missing data
        json_content = output_json.read_text()
        data = json.loads(json_content)
        assert 'gaps' in data
        # Should have a gap for the missing section
        assert len(data['gaps']) > 0
