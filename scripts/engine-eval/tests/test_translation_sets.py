"""Translation test sets: caption-style text, EdAcc caption lines, set builders (#159)."""
import json

from translation_eval.sets import (build_edacc_lines, build_flores, build_speech, caption_style, edacc_line,
                                   read_set, write_set)


def test_caption_style_lowercases_and_drops_sentence_punctuation():
    assert caption_style('Hello, Dr. Smith! "Really?" (yes) - fine.') == "hello dr smith really yes fine"


def test_caption_style_keeps_apostrophes_hyphens_and_digits_inside_words():
    assert caption_style("It's a well-known fact: 3.5 million people, in 2024.") == \
        "it's a well-known fact 3.5 million people in 2024"


def test_caption_style_keeps_accented_letters_and_collapses_space():
    assert caption_style("  Café   ÉCOLE…  ") == "café école"


def test_caption_style_drops_dashes_between_words_and_curly_quotes():
    assert caption_style("“Well” — he said – ‘no’") == "well he said no"


def test_caption_style_of_only_punctuation_is_empty():
    assert caption_style("?!...") == ""


def test_edacc_line_drops_tags_and_fillers():
    assert edacc_line("UM YEAH <laugh> I NEED TO CHILL <overlap> A LITTLE BIT UH") == "yeah i need to chill a little bit"


def test_edacc_line_rejects_too_short_too_long_and_ignored():
    assert edacc_line("MM YEAH") is None  # one word left
    assert edacc_line("IGNORE_TIME_SEGMENT_IN_SCORING") is None
    assert edacc_line(" ".join(["WORD"] * 41)) is None
    assert edacc_line(" ".join(["WORD"] * 40)) is not None


def _write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def test_build_flores_pairs_lines_and_groups_by_article(tmp_path):
    d = tmp_path / "flores200_dataset"
    _write(d / "devtest/eng_Latn.devtest", "One.\nTwo, too.\nThree.\n")
    _write(d / "devtest/spa_Latn.devtest", "Uno.\nDos, también.\nTres.\n")
    _write(d / "metadata_devtest.tsv", "URL\tdomain\ttopic\thas_image\thas_hyperlink\n"
                                       "http://a\twikinews\tx\t0\t0\nhttp://a\twikinews\tx\t0\t0\nhttp://b\twikinews\tx\t0\t0\n")
    clean, cap = build_flores(d, "spa_Latn")
    assert [r["source"] for r in clean] == ["One.", "Two, too.", "Three."]
    assert [r["source"] for r in cap] == ["one", "two too", "three"]
    assert [r["reference"] for r in cap] == ["Uno.", "Dos, también.", "Tres."]
    assert clean[0]["group"] == clean[1]["group"] != clean[2]["group"]
    assert [r["id"] for r in clean] == ["flores-0000", "flores-0001", "flores-0002"]
    assert {r["set"] for r in cap} == {"flores-caption"}


def test_build_flores_refuses_misaligned_files(tmp_path):
    d = tmp_path / "flores200_dataset"
    _write(d / "devtest/eng_Latn.devtest", "One.\nTwo.\n")
    _write(d / "devtest/spa_Latn.devtest", "Uno.\n")
    _write(d / "metadata_devtest.tsv", "URL\n" "a\n" "b\n")
    try:
        build_flores(d, "spa_Latn")
    except ValueError:
        return
    raise AssertionError("misaligned FLORES files must not build")


def test_build_speech_keeps_only_good_speech_segments(tmp_path):
    rows = [
        {"lp": "en-es_MX", "domain": "canary", "document_id": "c", "segment_id": 0, "is_bad_source": True,
         "source": "CANARY", "target": "CANARY"},
        {"lp": "en-es_MX", "domain": "news", "document_id": "n", "segment_id": 1, "is_bad_source": False,
         "source": "News.", "target": "Noticias."},
        {"lp": "en-es_MX", "domain": "speech", "document_id": "s1", "segment_id": 2, "is_bad_source": False,
         "source": "Okay, so look.", "target": "Bueno, mira."},
        {"lp": "en-es_MX", "domain": "speech", "document_id": "s2", "segment_id": 3, "is_bad_source": True,
         "source": "http://x", "target": "http://x"},
    ]
    p = _write(tmp_path / "en-es_MX.jsonl", "\n".join(json.dumps(r) for r in rows) + "\n")
    clean, cap = build_speech(p)
    assert [(r["id"], r["source"], r["reference"], r["group"]) for r in clean] == \
        [("speech-0002", "Okay, so look.", "Bueno, mira.", "s1")]
    assert cap[0]["source"] == "okay so look" and cap[0]["set"] == "speech-caption"


def test_build_edacc_lines_dedupes_and_has_no_reference(tmp_path):
    m = [{"clip_id": "a", "speaker": "S1", "reference": "UM I THINK SO"},
         {"clip_id": "b", "speaker": "S2", "reference": "I THINK SO <laugh>"},
         {"clip_id": "c", "speaker": "S2", "reference": "MM"},
         {"clip_id": "d", "speaker": "S3", "reference": "WE WENT TO THE BEACH"}]
    p = _write(tmp_path / "shard-001.jsonl", "\n".join(json.dumps(r) for r in m) + "\n")
    rows = build_edacc_lines([p])
    assert [(r["id"], r["source"], r["group"]) for r in rows] == \
        [("edacc-a", "i think so", "S1"), ("edacc-d", "we went to the beach", "S3")]
    assert all(r["reference"] is None for r in rows)


def test_write_and_read_set_roundtrip_unicode(tmp_path):
    rows = [{"id": "x", "set": "s", "group": "g", "source": "niño", "reference": "child"}]
    p = write_set(tmp_path / "out" / "s.jsonl", rows)
    assert read_set(p) == rows


def test_ids_are_unique_across_clean_and_caption_sets(tmp_path):
    # Result lines are keyed by id: a caption-style copy sharing ids with its clean set would be skipped on resume.
    d = tmp_path / "flores200_dataset"
    _write(d / "devtest/eng_Latn.devtest", "One.\nTwo.\n")
    _write(d / "devtest/spa_Latn.devtest", "Uno.\nDos.\n")
    _write(d / "metadata_devtest.tsv", "URL\n" "a\n" "b\n")
    clean, cap = build_flores(d, "spa_Latn")
    ids = [r["id"] for r in clean + cap]
    assert len(ids) == len(set(ids))
    assert cap[0]["id"] == "flores-caption-0000"
