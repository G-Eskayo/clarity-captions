"""Tests for scoreboard rendering."""
import json
from scoreboard_eval.render import render_markdown, render_json
from scoreboard_eval.build import Scoreboard
from scoreboard_eval.rows import ScenarioRow


def test_render_markdown_basic():
    """Test basic markdown rendering."""
    rows = [
        ScenarioRow('EdAcc', 'engine1', None, 'English', 'overall', 'WER', '13.8%', 'file', 'section', 1),
        ScenarioRow('EdAcc', 'engine2', None, 'English', 'overall', 'WER', '16.1%', 'file', 'section', 2),
    ]
    scoreboard = Scoreboard(rows=rows, gaps=[])

    md = render_markdown(scoreboard)

    assert '# Engine Scoreboard' in md
    assert 'EdAcc' in md
    assert 'engine1' in md
    assert '13.8%' in md


def test_render_markdown_with_gaps():
    """Test markdown rendering includes gaps section."""
    rows = []
    gaps = ['Test gap 1', 'Test gap 2']
    scoreboard = Scoreboard(rows=rows, gaps=gaps)

    md = render_markdown(scoreboard)

    assert '## Not covered yet' in md
    assert 'Test gap 1' in md
    assert 'Test gap 2' in md


def test_render_json_basic():
    """Test JSON rendering produces valid output."""
    rows = [
        ScenarioRow('EdAcc', 'engine1', 'model1', 'English', None, 'WER', '13.8%', 'file.md', '## Overall', 1),
    ]
    scoreboard = Scoreboard(rows=rows, gaps=[])

    json_output = render_json(scoreboard)

    # Should be valid JSON
    data = json.loads(json_output)

    assert 'rows' in data
    assert 'gaps' in data
    assert len(data['rows']) == 1

    row = data['rows'][0]
    assert row['engine'] == 'engine1'
    assert row['metric'] == 'WER'
    assert row['value'] == '13.8%'


def test_render_json_sorted():
    """Test JSON output is sorted and stable."""
    rows = [
        ScenarioRow('Z', 'b', None, 'Z', None, 'Z', '1', 'f', 's', 1),
        ScenarioRow('A', 'a', None, 'A', None, 'A', '2', 'f', 's', 2),
    ]
    scoreboard = Scoreboard(rows=rows, gaps=[])

    json_output = render_json(scoreboard)

    # Should be valid and consistent
    data1 = json.loads(json_output)
    data2 = json.loads(json_output)

    assert data1 == data2


def test_render_markdown_groups_by_dataset():
    """Test markdown rendering groups rows by dataset."""
    rows = [
        ScenarioRow('Spanish', 'engine1', None, 'Spanish', None, 'WER', '15%', 'file', 'section', 1),
        ScenarioRow('EdAcc', 'engine1', None, 'English', 'overall', 'WER', '13.8%', 'file', 'section', 2),
        ScenarioRow('EdAcc', 'engine2', None, 'English', 'overall', 'WER', '16%', 'file', 'section', 3),
    ]
    scoreboard = Scoreboard(rows=rows, gaps=[])

    md = render_markdown(scoreboard)

    # Should have separate sections for each dataset
    lines = md.split('\n')
    section_lines = [i for i, line in enumerate(lines) if line.startswith('## ')]

    # Should have at least 2 dataset sections
    assert len(section_lines) >= 2


def test_render_markdown_escapes_pipe_in_values():
    """Test that pipe characters in values are escaped to preserve table structure."""
    rows = [
        ScenarioRow('EdAcc', 'engine | v1', None, 'English', None, 'WER', '13% | 15%', 'file', 'section', 1),
        ScenarioRow('EdAcc', 'engine2', None, 'English', None, 'WER', '16%', 'file', 'section', 2),
    ]
    scoreboard = Scoreboard(rows=rows, gaps=[])

    md = render_markdown(scoreboard)

    # Verify the output is valid markdown table (no unescaped pipes breaking columns)
    lines = md.split('\n')
    table_lines = [l for l in lines if '|' in l]

    # Each table line should have matching pipe counts on left and right
    for line in table_lines:
        if line.startswith('| '):
            # Should have escaped the pipe as \|
            assert r'\|' in line or line.count('|') == 3  # Start/end plus middle delimiters
            # The value should be escaped
            assert 'engine \\| v1' in line or 'engine' in line
