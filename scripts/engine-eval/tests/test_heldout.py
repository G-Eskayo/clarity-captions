"""Held-out EdAcc calibration split and paired scoring (#272). Calibration speakers must never reach a scored number."""
import json
import random

import pytest

from edacc_eval.heldout import (choose_calibration_speakers, filter_manifest, load_split, paired_diff_ci,
                                split_record)


def corpus(seed=1):
    """Synthetic EdAcc-shaped manifest: two splits, disjoint speakers, some accents with one speaker only."""
    rng = random.Random(seed)
    rows = []
    accents = ["A", "B", "C", "D", "E", "F", "G"]
    spk_n = 0
    for split in ("validation", "test"):
        for acc in accents:
            for _ in range(3 if acc in "ABCD" else 1):
                spk = f"{split}-S{spk_n}"; spk_n += 1
                for j in range(5):
                    rows.append({"clip_id": f"{spk}-{j}", "split": split, "speaker": spk, "accent": acc,
                                 "audio_seconds": rng.uniform(1, 20), "reference": "A B"})
    # one accent that exists only once in the whole corpus, in validation
    rows += [{"clip_id": f"lonely-{j}", "split": "validation", "speaker": "lonely", "accent": "Z",
              "audio_seconds": 3.0, "reference": "A"} for j in range(5)]
    return rows


def test_calibration_speakers_come_only_from_validation():
    rows = corpus()
    spk = choose_calibration_speakers(rows, n=5)
    split_of = {r["speaker"]: r["split"] for r in rows}
    assert spk and all(split_of[s] == "validation" for s in spk)


def test_choice_is_deterministic_and_seeded():
    rows = corpus()
    assert choose_calibration_speakers(rows, n=4) == choose_calibration_speakers(list(reversed(rows)), n=4)
    picks = {tuple(choose_calibration_speakers(rows, n=4, seed=s)) for s in range(1, 9)}
    assert len(picks) > 1                                # the seed actually changes the pick


def test_never_takes_an_accents_last_scored_speaker():
    rows = corpus()
    spk = set(choose_calibration_speakers(rows, n=50))   # ask for far more than is safe
    assert "lonely" not in spk                          # the only Z speaker anywhere
    remaining = {(r["accent"]) for r in rows if r["speaker"] not in spk}
    assert remaining == {r["accent"] for r in rows}     # every accent still has a scored speaker


def test_at_most_one_speaker_per_accent():
    rows = corpus()
    spk = choose_calibration_speakers(rows, n=50)
    acc = {r["speaker"]: r["accent"] for r in rows}
    assert len({acc[s] for s in spk}) == len(spk)


def test_filter_never_returns_a_calibration_clip():
    rows = corpus()
    rec = split_record(rows, choose_calibration_speakers(rows, n=4))
    for part in ("test", "edacc-test"):
        got = filter_manifest(rows, rec, part)
        assert got and not {r["speaker"] for r in got} & set(rec["calibration"]["speakers"])
    cal = filter_manifest(rows, rec, "calibration")
    assert {r["speaker"] for r in cal} == set(rec["calibration"]["speakers"])
    assert {r["split"] for r in filter_manifest(rows, rec, "edacc-test")} == {"test"}


def test_unknown_part_is_refused():
    rows = corpus()
    rec = split_record(rows, choose_calibration_speakers(rows, n=2))
    with pytest.raises(ValueError):
        filter_manifest(rows, rec, "all")


def test_record_counts_add_up_and_round_trip(tmp_path):
    rows = corpus()
    rec = split_record(rows, choose_calibration_speakers(rows, n=3))
    assert rec["calibration"]["clips"] + rec["test"]["clips"] == len(rows)
    p = tmp_path / "split.json"
    p.write_text(json.dumps(rec))
    assert load_split(p) == rec


def test_load_split_refuses_a_tampered_record(tmp_path):
    rows = corpus()
    rec = split_record(rows, choose_calibration_speakers(rows, n=3))
    rec["calibration"]["speakers"] = rec["calibration"]["speakers"][1:]   # someone edits the list by hand
    p = tmp_path / "split.json"
    p.write_text(json.dumps(rec))
    with pytest.raises(ValueError):
        load_split(p)


def test_paired_diff_is_zero_for_identical_systems():
    a = {f"s{i}": (i + 3, 100) for i in range(30)}
    d, lo, hi = paired_diff_ci(a, dict(a))
    assert d == lo == hi == 0


def test_paired_diff_sign_and_ci_contain_truth():
    rng = random.Random(3)
    a, b = {}, {}
    for i in range(60):
        n = rng.randint(50, 400)
        e = int(n * rng.uniform(0.08, 0.2))
        a[f"s{i}"] = (e + int(n * 0.01), n)     # a is about 1 point worse
        b[f"s{i}"] = (e, n)
    truth = sum(a[k][0] - b[k][0] for k in a) / sum(a[k][1] for k in a)
    d, lo, hi = paired_diff_ci(a, b)
    assert d == pytest.approx(truth)
    assert 0 < lo < d < hi


def test_paired_ci_is_tighter_than_unpaired_when_systems_track_each_other():
    from edacc_eval.wer import bootstrap_ci
    rng = random.Random(4)
    a, b = {}, {}
    for i in range(60):
        n = rng.randint(50, 400)
        e = int(n * rng.uniform(0.05, 0.3))     # big between-speaker spread
        a[f"s{i}"] = (e + 1, n)
        b[f"s{i}"] = (e, n)
    _, lo, hi = paired_diff_ci(a, b)
    alo, ahi = bootstrap_ci(a)
    assert hi - lo < (ahi - alo) / 5


def test_paired_diff_refuses_different_speaker_sets():
    with pytest.raises(ValueError):
        paired_diff_ci({"a": (1, 10)}, {"b": (1, 10)})


def results_for(rows, model, wrong_every=0, drop=()):
    out = []
    for i, r in enumerate(rows):
        if r["clip_id"] in drop:
            continue
        hyp = "A" if wrong_every and i % wrong_every == 0 else r["reference"]
        out.append({"clip_id": r["clip_id"], "engine": "parakeet-fluidaudio", "model": model, "repeat": 1,
                    "hypothesis": hyp, "audio_seconds": r["audio_seconds"], "processing_seconds": 0.01,
                    "accent": r["accent"], "shard": 1})
    return out


def test_heldout_scores_skip_calibration_clips_even_when_they_are_the_only_errors():
    from edacc_eval.heldout import heldout_scores
    rows = corpus()
    rec = split_record(rows, choose_calibration_speakers(rows, n=3))
    cal = {r["clip_id"] for r in filter_manifest(rows, rec, "calibration")}
    # model "bad" is wrong on every calibration clip and right everywhere else
    bad = [dict(x, hypothesis="WRONG WRONG") if x["clip_id"] in cal else x for x in results_for(rows, "bad")]
    got = heldout_scores(rows, results_for(rows, "ref") + bad, rec, ref="ref")
    for part in ("test", "edacc-test"):
        assert got[part]["bad"]["wer"] == 0
        assert got[part]["bad"]["vs_ref"] == [0, 0, 0]


def test_heldout_scores_compare_only_clips_every_model_has():
    from edacc_eval.heldout import heldout_scores
    rows = corpus()
    rec = split_record(rows, choose_calibration_speakers(rows, n=3))
    test_ids = [r["clip_id"] for r in filter_manifest(rows, rec, "test")]
    got = heldout_scores(rows, results_for(rows, "ref") + results_for(rows, "b", drop={test_ids[0]}), rec, ref="ref")
    assert got["test"]["ref"]["clips"] == got["test"]["b"]["clips"] == len(test_ids) - 1


def test_heldout_scores_refuse_a_missing_reference_model():
    from edacc_eval.heldout import heldout_scores
    rows = corpus()
    rec = split_record(rows, choose_calibration_speakers(rows, n=3))
    with pytest.raises(ValueError):
        heldout_scores(rows, results_for(rows, "a"), rec, ref="ultra-pal6")


def conversations():
    """EdAcc naming: EDACC-C<conv>-A / -B are the two sides of one recorded conversation."""
    rows = []
    for conv, split, accs in [(1, "validation", ("X", "Y")), (2, "validation", ("X", "X")), (3, "test", ("X", "Y")),
                              (4, "validation", ("Y", "W")), (5, "test", ("W", "Y")), (6, "validation", ("V", "V"))]:
        for side, acc in zip("AB", accs):
            spk = f"EDACC-C{conv:02d}-{side}"
            rows += [{"clip_id": f"{spk}-{j}", "split": split, "speaker": spk, "accent": acc, "audio_seconds": 2.0,
                      "reference": "A"} for j in range(3)]
    return rows


def test_conversation_partners_are_held_out_together():
    from edacc_eval.heldout import conversation_of
    rows = conversations()
    spk = set(choose_calibration_speakers(rows, n=10))
    for s in spk:
        partner = s[:-1] + ("B" if s.endswith("A") else "A")
        assert partner in spk, f"{s} held out but its partner {partner} would be scored"
    assert conversation_of("EDACC-C04-A") == conversation_of("EDACC-C04-B") == "EDACC-C04"


def test_conversation_pick_still_leaves_every_accent_scored():
    rows = conversations()
    spk = set(choose_calibration_speakers(rows, n=10))
    assert {r["accent"] for r in rows if r["speaker"] not in spk} == {r["accent"] for r in rows}
    assert "EDACC-C06-A" not in spk          # V exists only in conversation 6: taking it would empty V
