"""Hebrew runners (#201): the registry the driver calls and the report's expected engines agree, and the streaming
flush pads every clip so the last words aren't lost."""
import numpy as np
import pytest

from edacc_eval.hebrew_run import ENGINES, padded_for_streaming
from edacc_eval.report_hebrew import EXPECTED


def test_every_python_engine_writes_a_model_name_the_report_knows():
    for spec in ENGINES.values():
        assert spec.model in EXPECTED


def test_python_engines_plus_apple_cover_every_expected_engine():
    assert {s.model for s in ENGINES.values()} | {"DictationTranscriber he-IL"} == set(EXPECTED)


def test_unknown_engine_is_refused():
    from edacc_eval.hebrew_run import run_engine
    with pytest.raises(KeyError):
        run_engine("nope", shard_dir=None, results=None, models_dir=None)


def test_streaming_flush_adds_tail_silence_and_keeps_the_audio():
    x = np.ones(16000, dtype=np.float32)
    y = padded_for_streaming(x, chunk_seconds=1.12)
    assert np.array_equal(y[:16000], x) and len(y) >= 16000 + int(2 * 1.12 * 16000)
    assert not y[16000:].any()
