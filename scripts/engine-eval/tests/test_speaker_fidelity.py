"""Choosing one compressed build per bit width on calibration audio only (#271 step 2)."""
import pytest

from speaker_eval import split as splitmod
from speaker_eval.fidelity import Candidate, IncompleteCalibration, choose, drift, parse_candidates
from speaker_eval.split import CalibrationLeak


def test_calibration_runs_refuse_test_recordings():
    sp = splitmod.load(set_name="ami")
    sp.require_calibration("ES2011a")
    with pytest.raises(CalibrationLeak):
        sp.require_calibration("IS1009a")      # a test meeting: never used to choose a build
    with pytest.raises(CalibrationLeak):
        sp.require_calibration("XX0000z")


def test_drift_is_zero_for_the_same_output_and_ignores_relabelling():
    base = [(0, 0.0, 5.0), (1, 5.0, 9.0)]
    assert drift(base, base, 10.0).errors == 0
    swapped = [(3, 0.0, 5.0), (2, 5.0, 9.0)]
    assert drift(base, swapped, 10.0).errors == 0     # slot numbers mean nothing: best mapping


def test_drift_counts_what_the_build_changed():
    base = [(0, 0.0, 5.0), (1, 5.0, 9.0)]
    lost = [(0, 0.0, 5.0)]                            # the build dropped the second speaker
    d = drift(base, lost, 10.0)
    assert d.miss == 400 and d.fa == 0 and d.ref == 900
    extra = base + [(2, 9.0, 10.0)]                    # and here added a second of speech fp16 didn't have
    assert drift(base, extra, 10.0).fa == 100


def test_candidates_parse_with_their_bit_widths():
    assert parse_candidates("pal8:8,int8:8,pal6:6") == [("pal8", 8), ("int8", 8), ("pal6", 6)]
    with pytest.raises(ValueError):
        parse_candidates("pal8")


def test_lowest_drift_wins_each_bit_width_and_ties_go_to_the_smaller_build():
    cands = [Candidate("pal8", 8, drift=0.020, mb=120.1), Candidate("int8", 8, drift=0.012, mb=120.4),
             Candidate("pal6", 6, drift=0.050, mb=92.6), Candidate("pal6g", 6, drift=0.050, mb=98.9)]
    assert choose(cands) == {8: "int8", 6: "pal6"}


def test_no_choice_on_partial_data():
    cands = [Candidate("pal8", 8, drift=0.02, mb=120.1, recordings=5), Candidate("int8", 8, drift=0.01, mb=120.4,
                                                                               recordings=6)]
    with pytest.raises(IncompleteCalibration):
        choose(cands, expected_recordings=6)


def test_an_excluded_build_is_shown_with_its_reason_not_dropped_silently():
    from speaker_eval.fidelity import markdown, parse_excluded
    assert parse_excluded(["int8=aborts at load"]) == {"int8": "aborts at load"}
    s = {"set": "ami", "base": "fp16", "recordings": ["ES2011a"], "base_bare_der_dev": 0.3, "chosen": {8: "pal8"},
         "candidates": [{"label": "pal8", "bits": 8, "drift": 0.01, "bare_der_dev": 0.3}],
         "excluded": {"int8": "aborts at load"}}
    md = markdown(s)
    assert "int8" in md and "aborts at load" in md
