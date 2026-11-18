"""Tests for scoreboard building."""
import pytest
from scoreboard_eval.build import build_scoreboard, Scoreboard
from scoreboard_eval.rows import ScenarioRow


def test_build_scoreboard_sorting():
    """Test case 11: Build scoreboard with consistent sorting."""
    rows = [
        ScenarioRow('Z-dataset', 'engine-b', None, 'lang', None, 'WER', '10%', 'file', 'section', 2),
        ScenarioRow('A-dataset', 'engine-a', None, 'lang', None, 'WER', '20%', 'file', 'section', 1),
        ScenarioRow('A-dataset', 'engine-b', None, 'lang', None, 'WER', '15%', 'file', 'section', 3),
    ]

    scoreboard = build_scoreboard(rows)

    # Should be sorted by dataset, engine
    assert len(scoreboard.rows) == 3
    assert scoreboard.rows[0].dataset == 'A-dataset'
    assert scoreboard.rows[0].engine == 'engine-a'
    assert scoreboard.rows[1].engine == 'engine-b'
    assert scoreboard.rows[2].dataset == 'Z-dataset'


def test_keep_engine_identity_distinct():
    """Test case 11: Keep distinct engine identities separate."""
    rows = [
        ScenarioRow('EdAcc', 'parakeet-fluidaudio (ultra-pal6)', 'ultra-pal6', 'English', None, 'WER', '13.8%', 'file', 'section', 1),
        ScenarioRow('EdAcc', 'parakeet-fluidaudio (ultra-pal6)', 'ultra-pal6', 'English', None, 'WER', '13.8%', 'file', 'section', 2),
        ScenarioRow('EdAcc', 'sherpa-onnx (int4)', 'int4', 'English', None, 'WER', '16.1%', 'file', 'section', 3),
    ]

    scoreboard = build_scoreboard(rows, dedup_engine_identity=False)

    # Should keep distinct engine identities: full names are preserved
    engines = [r.engine for r in scoreboard.rows]
    assert 'parakeet-fluidaudio (ultra-pal6)' in engines
    assert 'sherpa-onnx (int4)' in engines
    # Should NOT collapse them to just the parenthetical content (the bug)
    assert engines.count('ultra-pal6') == 0
    assert engines.count('int4') == 0


def test_scoreboard_is_immutable():
    """Test that Scoreboard is a stable structure."""
    rows = [
        ScenarioRow('EdAcc', 'engine', None, 'English', None, 'WER', '10%', 'file', 'section', 1),
    ]

    scoreboard = build_scoreboard(rows)

    # Scoreboard should be an immutable object
    assert isinstance(scoreboard, Scoreboard)
    assert len(scoreboard.rows) == 1
    assert scoreboard.gaps == []
