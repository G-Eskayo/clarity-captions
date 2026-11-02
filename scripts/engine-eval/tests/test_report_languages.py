"""Per-language scoring, sentence-group bootstrap, accent-blind WER, the verdict rule and the report (#158)."""
import json
import math

import pytest

from edacc_eval.report import Cell, recommend, score


def man(clip, ref, lang, group, gender="female"):
    return {"clip_id": clip, "reference": ref, "language": lang, "group": group, "speaker": "", "gender": gender,
            "accent": "x", "audio_seconds": 5.0, "file": f"audio/{clip}.wav"}


def r(clip, engine, hyp, model="m", proc=0.5):
    return {"clip_id": clip, "engine": engine, "model": model, "engine_version": "1", "repeat": 1,
            "hypothesis": hyp, "audio_seconds": 5.0, "processing_seconds": proc, "shard": 1}


def cell(wer, lo, hi):
    return Cell(wer=wer, ci_low=lo, ci_high=hi, sub=0, dele=0, ins=0, n=100, clips=10, speakers=5)


def test_language_aware_normalization_in_scoring():
    m = [man("f1", "Il a quatre-vingt-dix ans.", "fr", "g1")]
    s = score(m, [r("f1", "a", "il a 90 ans")])
    assert s.overall["a"].wer == 0.0


def test_english_manifest_without_language_still_scores_as_before():
    m = [{"clip_id": "e1", "reference": "OKAY I HAVE 3 KIDS", "speaker": "s1", "accent": "x", "audio_seconds": 2.0}]
    assert score(m, [r("e1", "a", "Ok, I have three kids.")]).overall["a"].wer == 0.0


def test_accent_only_errors_show_in_primary_but_not_accent_blind():
    m = [man("s1", "Está aquí", "es", "g1"), man("s2", "Hola amigo", "es", "g2")]
    s = score(m, [r("s1", "a", "esta aqui"), r("s2", "a", "hola amigo")])
    assert s.overall["a"].wer == 0.5
    assert s.accent_blind["a"] == 0.0


def test_bootstrap_resamples_groups_not_clips():
    # One sentence group: every resample is the same group, so the interval collapses to the point estimate.
    m = [man(f"c{i}", "uno dos", "es", "same") for i in range(6)]
    rows = [r(f"c{i}", "a", "uno dos" if i % 2 else "uno") for i in range(6)]
    c = score(m, rows).overall["a"]
    assert c.speakers == 1 and c.ci_low == c.ci_high == c.wer == 0.25
    # Distinct groups: the interval opens up.
    m2 = [man(f"c{i}", "uno dos", "es", f"g{i}") for i in range(6)]
    c2 = score(m2, rows).overall["a"]
    assert c2.speakers == 6 and c2.ci_low < c2.wer < c2.ci_high


# --- the verdict rule ------------------------------------------------------------------------------------------

def test_parakeet_when_ultra_matches_or_beats_apples_best_locale():
    v = recommend({"apple (es-MX)": cell(0.06, 0.05, 0.07), "apple (es-ES)": cell(0.08, 0.07, 0.09)},
                  cell(0.065, 0.055, 0.075))
    assert v.verdict == "Parakeet" and v.apple_label == "apple (es-MX)"


def test_apple_when_ultra_clearly_worse_than_apples_best():
    v = recommend({"apple": cell(0.05, 0.04, 0.06)}, cell(0.09, 0.08, 0.10))
    assert v.verdict == "Apple"


def test_ties_at_the_edges():
    assert recommend({"apple": cell(0.05, 0.04, 0.06)}, cell(0.07, 0.05, 0.09)).verdict == "Parakeet"  # lo == apple
    assert recommend({"apple": cell(0.20, 0.18, 0.22)}, cell(0.15, 0.14, 0.16)).verdict == "Parakeet"  # 15% is good


def test_not_ready_when_the_better_engine_misses_fifteen_percent():
    v = recommend({"apple": cell(0.20, 0.18, 0.22)}, cell(0.16, 0.15, 0.17))
    assert v.verdict == "not ready" and "16.0%" in v.reason


def test_missing_engine_is_not_ready_never_a_crash():
    assert recommend({}, cell(0.05, 0.04, 0.06)).verdict == "not ready"
    assert recommend({"apple": cell(0.05, 0.04, 0.06)}, None).verdict == "not ready"
    nan = cell(math.nan, math.nan, math.nan)
    assert recommend({"apple": nan}, nan).verdict == "not ready"


# --- the report ------------------------------------------------------------------------------------------------

def write_lang(root, lang, rows):
    d = root / lang / "shard-001"
    d.mkdir(parents=True)
    (d / "manifest.jsonl").write_text("\n".join(json.dumps(x) for x in rows) + "\n", encoding="utf-8")
    (root / lang / "index.json").write_text(json.dumps({"language": lang, "n_shards": 1, "shards": ["shard-001"]}))


def test_language_report_end_to_end(tmp_path):
    from edacc_eval.report import write_language_report
    shards, res = tmp_path / "shards", tmp_path / "results"
    res.mkdir()
    es = [man(f"es{i}", "Hola, ¿cómo estás?", "es", f"es-{i}") for i in range(4)]
    de = [man(f"de{i}", "Guten Morgen", "de", f"de-{i}") for i in range(4)]
    write_lang(shards, "es", es)
    write_lang(shards, "de", de)
    lines = []
    for i in range(4):
        lines += [r(f"es{i}", "apple-speechanalyzer", "hola como estas", model="SpeechTranscriber es-MX"),
                  r(f"es{i}", "apple-speechanalyzer", "ola como estás", model="SpeechTranscriber es-ES"),
                  r(f"es{i}", "parakeet-fluidaudio", "Hola, ¿cómo estás?", model="parakeet-ultra-coreml"),
                  r(f"es{i}", "sherpa-onnx", "hola cómo estás", model="v3"),
                  r(f"de{i}", "apple-speechanalyzer", "guten morgen", model="SpeechTranscriber de-DE"),
                  r(f"de{i}", "parakeet-fluidaudio", "gute morgen", model="parakeet-ultra-coreml")]
    (res / "lang-es.jsonl").write_text("\n".join(json.dumps(x) for x in lines) + "\n{broken\n")
    out = tmp_path / "out.md"
    result = write_language_report(shards, res, out, tmp_path / "out.json")
    md = out.read_text()
    assert result["es"].verdict.verdict == "Parakeet" and result["de"].verdict.verdict == "Apple"
    assert "## Spanish" in md and "## German" in md and "## French" not in md and "| French |" not in md
    assert "## Recommendation" in md and md.rstrip().splitlines()[-1].strip()  # ends with the recommendations
    assert "| Spanish | Parakeet |" in md and "| German | Apple |" in md
    assert "accent-blind" in md.lower() and "nan" not in md.lower()
    assert json.loads((tmp_path / "out.json").read_text())["es"]["verdict"] == "Parakeet"


def test_language_report_with_no_results(tmp_path):
    from edacc_eval.report import write_language_report
    shards, res = tmp_path / "shards", tmp_path / "results"
    res.mkdir()
    write_lang(shards, "fr", [man("f1", "Bonjour", "fr", "g")])
    result = write_language_report(shards, res, tmp_path / "o.md")
    md = (tmp_path / "o.md").read_text()
    assert result["fr"].verdict.verdict == "not ready" and "No results yet" in md and "nan" not in md.lower()


def test_report_says_when_apple_locales_give_identical_text(tmp_path):
    from edacc_eval.report import write_language_report
    shards, res = tmp_path / "shards", tmp_path / "results"
    res.mkdir()
    write_lang(shards, "es", [man(f"es{i}", "Hola amigo", "es", f"es-{i}") for i in range(3)])
    lines = []
    for i in range(3):
        lines += [r(f"es{i}", "apple-speechanalyzer", "hola amigo", model="SpeechTranscriber es-MX"),
                  r(f"es{i}", "apple-speechanalyzer", "hola amigo" if i else "ola amigo", model="SpeechTranscriber es-ES"),
                  r(f"es{i}", "parakeet-fluidaudio", "hola amigo", model="parakeet-ultra-coreml")]
    (res / "x.jsonl").write_text("\n".join(json.dumps(x) for x in lines) + "\n")
    write_language_report(shards, res, tmp_path / "o.md")
    assert "Apple's 2 Spanish locales gave identical text on 2 of 3 clips" in (tmp_path / "o.md").read_text()


def test_italian_and_portuguese_are_named_and_scored_for_234(tmp_path):
    from edacc_eval.report import write_language_report
    shards, res = tmp_path / "shards", tmp_path / "results"
    res.mkdir()
    write_lang(shards, "it", [man(f"it{i}", "Buongiorno a tutti", "it", f"it-{i}") for i in range(3)])
    write_lang(shards, "pt", [man(f"pt{i}", "Bom dia a todos", "pt", f"pt-{i}") for i in range(3)])
    lines = []
    for i in range(3):
        lines += [r(f"it{i}", "apple-speechanalyzer", "buongiorno a tutti", model="SpeechTranscriber it-IT"),
                  r(f"it{i}", "parakeet-fluidaudio", "buon giorno a tutti", model="parakeet-ultra-coreml"),
                  r(f"pt{i}", "apple-speechanalyzer", "bom dia todos", model="SpeechTranscriber pt-BR"),
                  r(f"pt{i}", "parakeet-fluidaudio", "Bom dia a todos.", model="parakeet-ultra-coreml")]
    (res / "x.jsonl").write_text("\n".join(json.dumps(x) for x in lines) + "\n")
    result = write_language_report(shards, res, tmp_path / "o.md")
    md = (tmp_path / "o.md").read_text()
    assert result["it"].verdict.verdict == "Apple" and result["pt"].verdict.verdict == "Parakeet"
    assert "## Italian" in md and "## Portuguese" in md and "| Portuguese | Parakeet |" in md
    assert "Spanish, French and German\"" not in md  # the header names the languages actually in the report
