"""Hebrew scoring (#201): the #202 normalizer on both sides, WER and CER with group-bootstrap CIs, strict and lenient
side by side, per test set, only clips every engine finished; and the generated report."""
import json
import math

from edacc_eval.report_hebrew import EXPECTED, build_hebrew_report, score_hebrew, write_hebrew_report


def man(clip, ref, group=None, test_set="he_il"):
    return {"clip_id": clip, "reference": ref, "language": "he", "group": group or clip, "speaker": "",
            "accent": test_set, "audio_seconds": 4.0, "file": f"audio/{clip}.wav"}


def r(clip, engine, hyp, model=None, proc=0.4):
    model = model or f"model-{engine}"
    return {"clip_id": clip, "engine": engine, "model": model, "engine_version": "1", "repeat": 1,
            "hypothesis": hyp, "audio_seconds": 4.0, "processing_seconds": proc, "shard": 1}


def only(scored, test_set="he_il"):
    (label, cell), = scored[test_set].cells.items()
    return cell


def test_niqqud_geresh_and_numbers_are_not_errors():
    m = [man("c1", "שָׁלוֹם, צה״ל קיבל חמישה טנקים.")]
    c = only(score_hebrew(m, [r("c1", "a", 'שלום צה"ל קיבל 5 טנקים')]))
    assert c.wer.value == 0.0 and c.cer.value == 0.0


def test_cer_is_reported_beside_wer_and_is_kinder_to_a_prefix_slip():
    m = [man("c1", "ובבית הספר")]
    c = only(score_hebrew(m, [r("c1", "a", "בבית הספר")]))
    assert c.wer.value == 0.5
    assert c.cer.value == 1 / len("ובבית הספר")


def test_strict_and_lenient_side_by_side():
    m = [man("c1", "השולחן גדול")]
    c = only(score_hebrew(m, [r("c1", "a", "השלחן גדול")]))
    assert c.wer.value == 0.5 and c.lenient_wer.value == 0.0
    assert c.cer.value > 0 and c.lenient_cer.value == 0.0


def test_only_clips_every_engine_finished_are_compared():
    m = [man("c1", "אחת"), man("c2", "שתיים")]
    s = score_hebrew(m, [r("c1", "a", "אחת"), r("c2", "a", "שגוי"), r("c1", "b", "אחת")])
    assert s["he_il"].clips_compared == 1
    assert s["he_il"].cells["model-a"].wer.value == 0.0 and s["he_il"].cells["model-b"].wer.value == 0.0


def test_an_engine_with_no_results_in_a_set_does_not_empty_the_comparison():
    m = [man("c1", "אחת", test_set="he_il"), man("d1", "שתיים", test_set="other")]
    s = score_hebrew(m, [r("c1", "a", "אחת"), r("d1", "a", "שתיים"), r("d1", "b", "שתיים")])
    assert s["he_il"].clips_compared == 1 and set(s["he_il"].cells) == {"model-a"}
    assert s["other"].clips_compared == 1 and set(s["other"].cells) == {"model-a", "model-b"}


def test_bootstrap_resamples_sentence_groups():
    rows = [r(f"c{i}", "a", "אחת שתיים" if i % 2 else "אחת") for i in range(6)]
    same = only(score_hebrew([man(f"c{i}", "אחת שתיים", group="g") for i in range(6)], rows))
    assert same.wer.low == same.wer.high == same.wer.value == 0.25
    spread = only(score_hebrew([man(f"c{i}", "אחת שתיים", group=f"g{i}") for i in range(6)], rows))
    assert spread.wer.low < spread.wer.value < spread.wer.high
    assert spread.cer.low < spread.cer.value < spread.cer.high
    assert spread.groups == 6


def test_empty_hypothesis_is_all_deletions_not_a_crash():
    c = only(score_hebrew([man("c1", "שלום עולם")], [r("c1", "a", "")]))
    assert c.wer.value == 1.0 and c.cer.value == 1.0


def test_speed_is_audio_over_processing():
    c = only(score_hebrew([man("c1", "שלום")], [r("c1", "a", "שלום", proc=0.5)]))
    assert math.isclose(c.x_realtime, 8.0)


def test_report_has_wer_and_cer_with_intervals_and_names_missing_engines():
    m = [man(f"c{i}", "שלום עולם", group=f"g{i}") for i in range(4)]
    rows = [r(f"c{i}", "sherpa-onnx-online", "שלום עולם" if i else "שלום", model="zipformer2-66m-streaming-he-int8")
            for i in range(4)]
    s = score_hebrew(m, rows)
    md = build_hebrew_report(s, {"generated_at": "2026-10-29 00:00 UTC", "sets": {"he_il": {"clips": 4}}})
    assert "ivrit.ai zipformer2 66M (sherpa-onnx, int8)" in md
    assert "| WER | 95% CI | CER | 95% CI | Lenient WER | Lenient CER |" in md
    assert "12.5%" in md  # 1 of 8 words
    for name in EXPECTED.values():
        if name != "ivrit.ai zipformer2 66M (sherpa-onnx, int8)":
            assert name in md.split("## Not run")[1]  # every engine with no result is listed, with no silent gaps


def test_write_report_reads_shards_and_results(tmp_path):
    shards = tmp_path / "shards" / "he"
    (shards / "shard-001").mkdir(parents=True)
    (shards / "index.json").write_text(json.dumps({"shards": ["shard-001"], "config": "he_il", "clips": 1,
                                                    "sentences": 1, "audio_hours": 0.001}))
    (shards / "shard-001" / "manifest.jsonl").write_text(json.dumps(man("c1", "שלום"), ensure_ascii=False) + "\n")
    res = tmp_path / "results"
    res.mkdir()
    (res / "x.jsonl").write_text(json.dumps(r("c1", "apple-dictation", "שלום", model="DictationTranscriber he-IL"),
                                            ensure_ascii=False) + "\n")
    out = tmp_path / "report.md"
    write_hebrew_report(tmp_path / "shards", res, out, tmp_path / "report.json")
    text = out.read_text()
    assert "Apple DictationTranscriber he-IL" in text and "0.0%" in text
    assert json.loads((tmp_path / "report.json").read_text())["he_il"]["clips_compared"] == 1


def test_one_model_name_under_two_engines_is_refused_not_merged():
    import pytest
    with pytest.raises(ValueError):
        score_hebrew([man("c1", "שלום")], [r("c1", "a", "שלום", model="same"), r("c1", "b", "שלום", model="same")])
