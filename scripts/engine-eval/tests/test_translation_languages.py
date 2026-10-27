"""Apple all-languages table: which system assets a pair needs, row scoring, sort order (#159 follow-up)."""
import math

import pytest

pytest.importorskip("sacrebleu")

from translation_eval.languages import APPLE_FLORES, NAMES, languages_table, language_row, pair_assets

SPECS = [
    "com.apple.sequoia.asset.mt.bi-en-es-de-it-fr-pt-nl.20",
    "com.apple.sequoia.asset.mt.bi-en-es-de-it-fr-pt-nl.en.20",
    "com.apple.sequoia.asset.mt.bi-en-es-de-it-fr-pt-nl.es.20",
    "com.apple.sequoia.asset.mt.bi-en-zh-ja-ko.20",
    "com.apple.sequoia.asset.mt.bi-en-zh-ja-ko.en.20",
    "com.apple.sequoia.asset.mt.bi-en-zh-ja-ko.zh.20",
    "com.apple.sequoia.asset.mt.bi-en-ar.20",
    "com.apple.sequoia.asset.mt.bi-en-ar.en.20",
    "com.apple.sequoia.asset.mt.bi-en-ar.ar.20",
    "com.apple.sequoia.asset.asr.es_ES",
    "com.apple.sequoia.asset.pb.es",
]


def test_pair_assets_takes_family_shared_english_and_target():
    fam = "com.apple.sequoia.asset.mt.bi-en-es-de-it-fr-pt-nl"
    assert pair_assets(SPECS, "es") == [f"{fam}.20", f"{fam}.en.20", f"{fam}.es.20"]


def test_pair_assets_region_codes_use_the_base_language():
    assert pair_assets(SPECS, "zh-TW")[-1].endswith("bi-en-zh-ja-ko.zh.20")
    assert pair_assets(SPECS, "ar-AE")[-1].endswith("bi-en-ar.ar.20")


def test_pair_assets_missing_target_asset_is_unknown_not_a_partial_sum():
    # de is in the family's name, but its own asset isn't installed
    assert pair_assets(SPECS, "de") == []
    assert pair_assets(SPECS, "sv") == []
    # "en" must not match a family just because every family name has it
    assert pair_assets(SPECS, "en") == []


def test_every_language_has_a_name_and_a_flores_code():
    assert set(APPLE_FLORES) == set(NAMES)


def _rows(ids, hyp, rep=1, secs=0.05):
    return [{"clip_id": i, "engine": "apple", "model": "apple-en-xx", "repeat": rep, "hypothesis": hyp(i),
             "processing_seconds": secs, "audio_seconds": 0} for i in ids]


SETS = {
    "flores": [{"id": f"flores-{i}", "set": "flores", "group": f"g{i % 4}", "source": f"s{i}",
                "reference": f"la referencia {i}"} for i in range(12)],
    "edacc-lines": [{"id": f"edacc-{i}", "set": "edacc-lines", "group": "sp", "source": f"hello {i}",
                     "reference": None} for i in range(20)],
}


def test_language_row_scores_flores_and_times_caption_lines():
    f = [r["id"] for r in SETS["flores"]]
    e = [r["id"] for r in SETS["edacc-lines"]]
    rows = _rows(f, lambda i: f"la referencia {i.split('-')[1]}") + _rows(e, lambda i: "hola", secs=0.04) \
        + _rows(e, lambda i: "hola", rep=2, secs=0.06)
    r = language_row("xx", SETS, rows, disk_bytes=123, n_boot=50)
    assert r["chrf"] == pytest.approx(100.0)
    assert r["n"] == 12
    assert 40 <= r["median_ms"] <= 60
    assert r["untranslated"] == 0
    assert r["disk_bytes"] == 123
    assert r["comet"] is None


def test_language_row_without_results_is_nan_not_a_crash():
    r = language_row("xx", SETS, [], n_boot=10)
    assert math.isnan(r["chrf"]) and r["median_ms"] is None


def test_table_sorts_best_first_and_puts_missing_scores_last():
    rows = [
        {"code": "a", "name": "A", "chrf": 40.0, "ci": (39.0, 41.0), "median_ms": 50, "p95_ms": 80, "disk_bytes": None},
        {"code": "b", "name": "B", "chrf": math.nan, "ci": (math.nan, math.nan), "median_ms": None, "p95_ms": None},
        {"code": "c", "name": "C", "chrf": 60.0, "ci": (59.0, 61.0), "median_ms": 70, "p95_ms": 90,
         "disk_bytes": 286_000_000},
    ]
    lines = languages_table(rows).splitlines()
    assert [l.split("|")[1].strip() for l in lines[2:]] == ["C", "A", "B"]
    assert "286 MB" in lines[2] and "| – |" in lines[3]
