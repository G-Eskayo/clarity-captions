"""#271 speaker scoreboard: tests that try to break the scorer, the caption stream and the split guard."""
import itertools
import json
import random

import pytest

from speaker_eval import cli, split as splitmod
from speaker_eval.der import best_mapping, der
from speaker_eval.reference import Seg, long_monologues, phrases, read_rttm, turns
from speaker_eval.score import bootstrap, pooled, score_recording, summary

U = (0.0, 20.0)


# ---- DER ----------------------------------------------------------------------------------------------------------

def test_perfect_hypothesis_scores_zero_whatever_the_labels_are_called():
    ref = [("A", 0, 5), ("B", 5, 10)]
    assert der(ref, [(7, 0, 5), (3, 5, 10)], U).der == 0


def test_no_hypothesis_is_all_missed():
    c = der([("A", 0, 5), ("B", 5, 10)], [], U)
    assert c.der == 1 and c.miss == c.ref and c.fa == c.conf == 0


def test_one_label_for_two_people_charges_the_smaller_one_as_confusion():
    c = der([("A", 0, 7), ("B", 7, 10)], [(0, 0, 10)], U)
    assert c.conf == 300 and c.miss == c.fa == 0 and c.ref == 1000


def test_overlap_counts_once_per_speaker_and_one_hyp_label_misses_the_other():
    c = der([("A", 0, 10), ("B", 4, 6)], [(0, 0, 10)], U)
    assert c.ref == 1200 and c.miss == 200 and c.conf == 0


def test_speech_in_silence_is_false_alarm():
    c = der([("A", 0, 5)], [(0, 0, 5), (0, 8, 9)], U)
    assert c.fa == 100 and c.der == pytest.approx(0.2)


def test_extra_hypothesis_speaker_is_confusion_not_free():
    # One person, model splits them into two labels: half the time is wrong.
    c = der([("A", 0, 10)], [(0, 0, 5), (1, 5, 10)], U)
    assert c.conf == 500 and c.der == pytest.approx(0.5)


def test_only_scored_inside_the_uem():
    c = der([("A", 0, 10)], [], (2.0, 4.0))
    assert c.ref == 200


def test_mapping_is_optimal_against_brute_force():
    rng = random.Random(3)
    for _ in range(200):
        R, H = rng.randint(1, 4), rng.randint(1, 6)
        m = [[rng.randint(0, 50) for _ in range(H)] for _ in range(R)]
        best = 0
        for perm in itertools.permutations(range(H), min(R, H)):
            for rows in itertools.combinations(range(R), min(R, H)):
                best = max(best, sum(m[r][c] for r, c in zip(rows, perm)))
        total, mapping = best_mapping(m)
        assert total == best
        assert len(set(mapping.values())) == len(mapping)  # one-to-one


# ---- caption stream -----------------------------------------------------------------------------------------------

def _is_stream(ph):
    return all(p.end > p.start for p in ph) and all(b.start >= a.end - 1e-9 for a, b in zip(ph, ph[1:]))


def test_lines_never_overlap_and_cover_all_speech():
    rng = random.Random(9)
    for _ in range(100):
        segs = []
        for _ in range(rng.randint(1, 30)):
            s = rng.uniform(0, 100)
            segs.append(Seg(rng.choice("ABCD"), s, s + rng.uniform(0.05, 25)))
        ph = phrases(segs)
        assert _is_stream(ph)
        speech = sum(t.end - t.start for t in _union(turns(segs)))
        assert sum(p.end - p.start for p in ph) == pytest.approx(speech)
        assert all(p.end - p.start <= 10.0 + 1e-9 for p in ph)


def _union(segs):
    out = []
    for s in sorted(segs, key=lambda s: s.start):
        if out and s.start <= out[-1].end:
            out[-1] = Seg("x", out[-1].start, max(out[-1].end, s.end))
        else:
            out.append(Seg("x", s.start, s.end))
    return out


def test_someone_cutting_in_takes_the_line_then_it_goes_back():
    ph = phrases([Seg("A", 0, 8), Seg("B", 3, 4)])
    assert [(p.truth, p.start, p.end) for p in ph] == [("A", 0, 3), ("B", 3, 4), ("A", 4, 8)]


def test_a_breath_is_not_a_new_line_but_a_long_pause_is():
    assert len(phrases([Seg("A", 0, 2), Seg("A", 2.3, 4)])) == 1
    assert len(phrases([Seg("A", 0, 2), Seg("A", 3.0, 4)])) == 2


def test_long_talk_is_cut_into_equal_lines():
    ph = phrases([Seg("A", 0, 25)])
    assert len(ph) == 3 and all(p.truth == "A" for p in ph)
    assert ph[-1].end == 25 and ph[0].end - ph[0].start == pytest.approx(25 / 3)


def test_monologue_survives_a_backchannel_but_not_a_short_talk():
    segs = [Seg("A", 0, 12), Seg("B", 6, 6.4), Seg("A", 13, 26), Seg("C", 30, 35)]
    assert [(m.speaker, m.start, m.end) for m in long_monologues(segs)] == [("A", 0, 26)]


def test_rttm_reader_skips_zero_length_and_sorts(tmp_path):
    f = tmp_path / "x.rttm"
    f.write_text("SPEAKER M 1 5.0 1.0 <NA> <NA> B <NA> <NA>\nSPEAKER M 1 1.0 0.0 <NA> <NA> A <NA> <NA>\n"
                 "SPEAKER M 1 0.5 1.0 <NA> <NA> A <NA> <NA>\n")
    assert read_rttm(f)["M"] == [Seg("A", 0.5, 1.5), Seg("B", 5.0, 6.0)]


# ---- split guard --------------------------------------------------------------------------------------------------

def test_frozen_split_is_disjoint_and_complete():
    ami, chime = splitmod.load(set_name="ami"), splitmod.load(set_name="chime6")
    assert len(ami.test) == 16 and len(chime.test) == 31
    assert len(ami.calibration) == 18 + 27 and ami.calibration == chime.calibration
    assert not (set(ami.test) | set(chime.test)) & ami.calibration
    assert all(r[:3] in ("S01", "S21") for r in chime.test)


def test_a_set_cannot_score_the_other_sets_test_recordings():
    with pytest.raises(splitmod.CalibrationLeak):
        splitmod.load(set_name="ami").require_test("S01w00")


def test_unknown_set_is_an_error():
    with pytest.raises(ValueError):
        splitmod.load(set_name="voxconverse")


def test_calibration_and_unknown_recordings_are_refused():
    sp = splitmod.load()
    with pytest.raises(splitmod.CalibrationLeak):
        sp.require_test("IS1008a")
    with pytest.raises(splitmod.CalibrationLeak):
        splitmod.load(set_name="chime6").require_test("S02w04")  # CHiME-6 dev
    with pytest.raises(splitmod.CalibrationLeak):
        sp.require_test("ES2002a")  # AMI train: not in the split at all
    sp.require_test("ES2004a")


def test_split_file_with_a_recording_in_both_slices_fails_to_load(tmp_path):
    f = tmp_path / "s.json"
    f.write_text(json.dumps({"sets": {"a": {"calibration": ["X", "Y"], "test": ["Z"]},
                                      "b": {"calibration": [], "test": ["Y"]}}}))
    with pytest.raises(ValueError):
        splitmod.load(f)


def test_score_command_stops_on_a_calibration_result(tmp_path):
    (tmp_path / "IS1008a.fp16.r1.json").write_text("{}")
    with pytest.raises(splitmod.CalibrationLeak):
        cli.main(["score", "--rttm-dir", str(tmp_path), "--uem-dir", str(tmp_path), "--results", str(tmp_path),
                  "--model", "fp16", "--out-md", str(tmp_path / "o.md"), "--out-json", str(tmp_path / "o.json")])


def test_score_command_refuses_an_incomplete_run(tmp_path):
    (tmp_path / "ES2004a.fp16.r1.json").write_text("{}")
    rc = cli.main(["score", "--rttm-dir", str(tmp_path), "--uem-dir", str(tmp_path), "--results", str(tmp_path),
                   "--model", "fp16", "--out-md", str(tmp_path / "o.md"), "--out-json", str(tmp_path / "o.json")])
    assert rc == 2


# ---- per-recording scoring ----------------------------------------------------------------------------------------

def _result(ph, labels, segments=None, rec="ES2004a"):
    em = [{"now": p.end + 1, "phrase": i, "final": True, "label": l, "raw": l} for i, (p, l) in enumerate(zip(ph, labels))]
    return {"recording": rec, "phrases": len(ph), "emissions": em, "segments": segments or [],
            "audio_seconds": 30.0, "wall_seconds": 1.0, "load_seconds": 0.5,
            "chunk_ms": {"p95": 3.0, "max": 9.0}, "footprint_mb": {"peak": 300.0, "lifetime_peak": 310.0}}


def test_true_labels_on_screen_equal_the_floor():
    ref = [Seg("A", 0, 8), Seg("B", 3, 4), Seg("C", 10, 14)]
    ph = phrases(ref)
    labels = [{"A": 0, "B": 1, "C": 2}[p.truth] for p in ph]
    s = score_recording(_result(ph, labels), ref, ph, (0, 20))
    assert s.live.der == s.floor.der
    assert s.floor.miss == 100  # A's speech underneath B's line
    assert s.shown_speakers == s.ref_speakers == 3
    assert s.peak_mb == 310.0


def test_monologue_split_across_two_labels_is_counted():
    ref = [Seg("A", 0, 25)]
    ph = phrases(ref)
    s = score_recording(_result(ph, [0, 1, 1]), ref, ph, (0, 30))
    assert s.monologues == [(True, pytest.approx(2 / 3))]
    assert s.shown_speakers == 2


def test_result_built_from_different_lines_is_rejected():
    ref = [Seg("A", 0, 25)]
    ph = phrases(ref)
    with pytest.raises(ValueError):
        score_recording(_result(ph[:2], [0, 0]), ref, ph, (0, 30))


def test_bootstrap_is_reproducible_and_brackets_the_estimate():
    recs = []
    for k in range(8):
        ref = [Seg("A", 0, 5 + k), Seg("B", 10, 15)]
        ph = phrases(ref)
        recs.append(score_recording(_result(ph, [0, 0 if k % 2 else 1], rec=f"R{k}"), ref, ph, (0, 20)))
    f = lambda x: pooled(x, "live")
    assert bootstrap(recs, f) == bootstrap(recs, f)
    lo, hi = bootstrap(recs, f)
    assert lo <= f(recs) <= hi and lo < hi
    s = summary(recs)
    assert s["recordings"] == 8 and 0 < s["der_live"]["value"] < 1


# ---- CHiME-6 windows ----------------------------------------------------------------------------------------------

from speaker_eval.chime6 import Window, hms, window_reference, windows


def _u(spk, s, e, ref="U01"):
    return {"speaker": spk, "start": s, "end": e, "ref": ref, "session": "S99"}


def test_hms_parses_the_transcript_clock():
    assert hms("02:39:01.74") == pytest.approx(9541.74)


def test_windows_cover_the_session_and_a_short_tail_joins_the_last_window():
    ws = windows([_u("P1", 0, 100), _u("P2", 1500, 1720)], "S99", window=600)
    assert [(w.start, w.end) for w in ws] == [(0, 600), (600, 1200), (1200, 1720)]
    assert [w.recording for w in ws] == ["S99w00", "S99w01", "S99w02"]


def test_a_long_tail_is_its_own_window():
    ws = windows([_u("P1", 0, 100), _u("P2", 1500, 1550)], "S99", window=600)
    assert ws[-1].start == 1200 and ws[-1].end == 1550 and len(ws) == 3


def test_window_array_is_where_most_of_its_talking_is():
    ws = windows([_u("P1", 0, 50, "U02"), _u("P2", 60, 400, "U06"), _u("P3", 400, 590, "U02")], "S99", window=600)
    assert ws[0].array == "U06"


def test_window_reference_is_local_time_and_cut_at_the_edges():
    w = Window("S99w01", "S99", "U01", 600, 1200)
    ref = window_reference([_u("P1", 590, 610), _u("P2", 1190, 1300), _u("P3", 10, 20)], w)
    assert [(s.speaker, s.start, s.end) for s in ref] == [("P1", 0, 10), ("P2", 590, 600)]
