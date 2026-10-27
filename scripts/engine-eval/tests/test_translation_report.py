"""Translation report assembly: common segments, failure checks, determinism, markdown (#159)."""
import pytest

pytest.importorskip("sacrebleu")

from translation_eval.report import build_report, common_ids, line_checks, score_pair

SETS = {
    "flores": [{"id": f"f{i}", "set": "flores", "group": f"g{i % 3}", "source": f"src {i}", "reference": f"ref {i}"}
               for i in range(6)],
    "edacc-lines": [{"id": f"e{i}", "set": "edacc-lines", "group": "s", "source": f"hello there {i}",
                     "reference": None} for i in range(8)],
}


def res(engine, model, ids, hyp=lambda i: i, rep=1, secs=0.01, bs=1):
    return [{"clip_id": i, "accent": i[0], "engine": engine, "model": model, "repeat": rep, "hypothesis": hyp(i),
             "processing_seconds": secs, "batch_size": bs, "audio_seconds": 0} for i in ids]


def test_common_ids_only_keeps_segments_every_engine_finished():
    rows = res("a", "m", ["f0", "f1", "f2"]) + res("b", "n", ["f1", "f2", "f3"])
    assert common_ids(rows, ["f0", "f1", "f2", "f3"]) == ["f1", "f2"]


def test_line_checks_count_untranslated_empty_and_determinism():
    src = {r["id"]: r["source"] for r in SETS["edacc-lines"]}
    r1 = res("a", "m", list(src), hyp=lambda i: src[i] if i == "e0" else ("" if i == "e1" else "hola"))
    r2 = res("a", "m", list(src), hyp=lambda i: "x" if i == "e2" else (src[i] if i == "e0" else ("" if i == "e1" else "hola")),
             rep=2)
    c = line_checks(r1 + r2, src)
    assert c["untranslated"] == 1 and c["empty"] == 1 and c["lines"] == 8
    assert c["identical_repeats"] == pytest.approx(7 / 8)


def test_score_pair_ranks_engines_and_scores_only_common_segments():
    flores = SETS["flores"]
    good = res("good", "g", [r["id"] for r in flores], hyp=lambda i: f"ref {i[1:]}", bs=8)
    bad = res("bad", "b", [r["id"] for r in flores][:5], hyp=lambda i: "nada", bs=8)
    s = score_pair(SETS, good + bad, comet={}, n_boot=100)
    cell = s["sets"]["flores"]
    assert cell["n"] == 5
    assert [e["engine"] for e in cell["engines"]] == ["good", "bad"]
    assert cell["engines"][0]["chrf"] == pytest.approx(100.0)
    assert cell["engines"][1]["diff_vs_best"][0] < 0


def test_report_markdown_has_tables_and_marks_missing_engines():
    rows = res("opus-mt", "opus-mt-en-es", [r["id"] for r in SETS["flores"]], hyp=lambda i: f"ref {i[1:]}", bs=8)
    rows += res("opus-mt", "opus-mt-en-es", [r["id"] for r in SETS["edacc-lines"]])
    s = score_pair(SETS, rows, comet={}, n_boot=50)
    md = build_report({"en-es": s}, {"generated": "2026-10-26", "sizes": {}, "missing": {"apple": "not installed"}})
    assert "## en-es" in md and "| opus-mt " in md
    assert "apple" in md and "not installed" in md


def test_speed_rows_from_an_isolated_pass_replace_the_main_runs_timing():
    ids = [r["id"] for r in SETS["edacc-lines"]]
    main = res("opus-mt", "m", ids, secs=1.0)
    clean = res("opus-mt", "m", ids, secs=0.05)
    s = score_pair(SETS, main, comet={}, n_boot=10, speed_rows=clean)
    assert s["speed"][0]["speed"]["median_ms"] == pytest.approx(50.0)
    assert score_pair(SETS, main, comet={}, n_boot=10)["speed"][0]["speed"]["median_ms"] == pytest.approx(1000.0)
