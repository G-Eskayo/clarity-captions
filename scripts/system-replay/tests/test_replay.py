"""Tests for the whole-system replay's stitcher and scorer (#273). Run: python -m pytest scripts/system-replay/tests"""
from __future__ import annotations

import json
import math
import struct
import wave
from pathlib import Path

import pytest

import replay


def write_wav(path: Path, samples: list[int], rate: int = 16_000) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def clip(cid: str, split: str, speaker: str, ref: str, secs: float) -> dict:
    return {"clip_id": cid, "split": split, "speaker": speaker, "accent": "A", "reference": ref,
            "audio_seconds": secs, "file": f"audio/{cid}.wav"}


# --- conversation ids -------------------------------------------------------------------------------------------

def test_conversation_and_segment_from_clip_id():
    assert replay.conversation_of("test-EDACC-C34-9") == ("EDACC-C34", 9)
    assert replay.conversation_of("validation-EDACC-C23_P1-145") == ("EDACC-C23_P1", 145)
    with pytest.raises(ValueError):
        replay.conversation_of("EDACC-C34-9")   # no split prefix: refuse rather than guess


# --- stitching --------------------------------------------------------------------------------------------------

def test_stitch_orders_by_segment_number_not_text_and_records_windows(tmp_path):
    shard = tmp_path / "shard"
    (shard / "audio").mkdir(parents=True)
    rows = [clip("test-EDACC-C1-10", "test", "C1-A", "TEN", 0.5),
            clip("test-EDACC-C1-9", "test", "C1-B", "NINE", 0.25),
            clip("validation-EDACC-C2-1", "validation", "C2-A", "DEV", 0.25),
            clip("test-EDACC-C1-11", "test", "C1-A", "<NO-SPEECH>", 0.25)]
    for r, n in zip(rows, (8000, 4000, 4000, 4000)):
        write_wav(shard / r["file"], [1000] * n)
    (shard / "manifest.jsonl").write_text("\n".join(json.dumps(r) for r in rows))
    out = tmp_path / "out"
    convs = replay.stitch(shard, out, split="test", gap_seconds=1.0, tail_seconds=3.0)
    assert [c["id"] for c in convs] == ["test-EDACC-C1"]
    c = convs[0]
    # "9" before "10": numeric order. The empty-after-normalisation segment is dropped, as #145 drops it.
    assert [s["clip_id"] for s in c["segments"]] == ["test-EDACC-C1-9", "test-EDACC-C1-10"]
    assert c["segments"][0]["start"] == 0.0 and c["segments"][0]["end"] == 0.25
    assert c["segments"][1]["start"] == 1.25 and c["segments"][1]["end"] == 1.75
    with wave.open(str(out / c["file16k"])) as w:
        assert w.getframerate() == 16_000
        assert w.getnframes() == int((0.25 + 1.0 + 0.5 + 3.0) * 16_000)
    assert c["speakers"] == ["C1-A", "C1-B"]


def test_stitch_refuses_a_clip_whose_audio_does_not_match_its_manifest_length(tmp_path):
    shard = tmp_path / "shard"
    (shard / "audio").mkdir(parents=True)
    r = clip("test-EDACC-C1-1", "test", "C1-A", "HI", 1.0)
    write_wav(shard / r["file"], [0] * 8000)   # 0.5 s, manifest says 1.0 s
    (shard / "manifest.jsonl").write_text(json.dumps(r))
    with pytest.raises(ValueError, match="length"):
        replay.stitch(shard, tmp_path / "o", split="test", gap_seconds=1, tail_seconds=0)


def test_stitch_refuses_a_non_16k_mono_clip(tmp_path):
    shard = tmp_path / "shard"
    (shard / "audio").mkdir(parents=True)
    r = clip("test-EDACC-C1-1", "test", "C1-A", "HI", 0.5)
    write_wav(shard / r["file"], [0] * 4000, rate=8000)
    (shard / "manifest.jsonl").write_text(json.dumps(r))
    with pytest.raises(ValueError, match="16"):
        replay.stitch(shard, tmp_path / "o", split="test", gap_seconds=1, tail_seconds=0)


# --- hypothesis text from a session ---------------------------------------------------------------------------

def test_session_text_is_the_lines_she_reads_without_sound_labels():
    log = {"lines": [{"text": "hello there", "speaker": 0, "soundLabel": None},
                     {"text": "", "speaker": None, "soundLabel": "laughter"},
                     {"text": "bye", "speaker": 1, "soundLabel": None}]}
    assert replay.session_text(log) == "hello there bye"


def test_a_session_with_an_error_is_refused_not_scored_as_silence():
    with pytest.raises(ValueError, match="error"):
        replay.session_text({"lines": [], "error": "timed out"})


# --- paired scoring ---------------------------------------------------------------------------------------------

def test_paired_gap_is_zero_when_both_arms_are_identical():
    units = {f"c{i}": ((i % 3, 10), (i % 3, 10)) for i in range(30)}
    g = replay.paired_gap(units, n_boot=200)
    assert g["a"] == g["b"]
    assert g["gap"] == 0 and g["lo"] == 0 and g["hi"] == 0


def test_paired_gap_ci_excludes_zero_for_a_consistent_regression_and_includes_it_for_noise():
    worse = {f"c{i}": ((1, 20), (4, 20)) for i in range(40)}           # b always 3 more errors in 20 words
    g = replay.paired_gap(worse, n_boot=500)
    assert g["gap"] == pytest.approx(0.15)
    assert g["lo"] > 0
    noisy = {f"c{i}": ((2, 20), (2 + (1 if i % 2 else -1), 20)) for i in range(40)}
    g2 = replay.paired_gap(noisy, n_boot=500)
    assert g2["lo"] <= 0 <= g2["hi"]


def test_paired_gap_resamples_conversations_together_so_a_pair_is_never_split():
    # Arm b is worse only on conversations with few words; a resample that split pairs would wander far wider.
    units = {"big": ((10, 1000), (10, 1000)), "small": ((0, 10), (5, 10))}
    g = replay.paired_gap(units, n_boot=300)
    # Every resample is some mix of big/small pairs: the gap is always between 0 and 5/10.
    assert 0 <= g["lo"] <= g["hi"] <= 0.5


def test_percentile_of_small_lists():
    assert replay.percentile([3.0], 0.5) == 3.0
    assert replay.percentile([1.0, 2.0, 3.0, 4.0], 0.5) == 2.5
    assert math.isnan(replay.percentile([], 0.5))


def test_score_arm_pools_errors_over_words_and_counts_engines(tmp_path):
    convs = [{"id": "test-EDACC-C1", "reference": "hello there friend",
              "segments": [{"clip_id": "test-EDACC-C1-1", "reference": "HELLO THERE FRIEND"}]},
             {"id": "test-EDACC-C2", "reference": "good morning",
              "segments": [{"clip_id": "test-EDACC-C2-1", "reference": "GOOD MORNING"}]}]
    logs = {"test-EDACC-C1": {"lines": [{"text": "Hello there, friend.", "soundLabel": None}], "plan": {"engine": "parakeet"},
                              "enginesSeen": [{"name": "parakeet-ultra-pal6", "firstAt": 1}], "fallbacks": [],
                              "updates": [{"lag": 0.4}, {"lag": 0.6}, {"lag": None}]},
            "test-EDACC-C2": {"lines": [{"text": "good", "soundLabel": None}], "plan": {"engine": "parakeet"},
                              "enginesSeen": [{"name": "apple-speechanalyzer", "firstAt": 1}],
                              "fallbacks": [{"reason": "noWordsFromSpeech", "at": 20}], "updates": [{"lag": 1.0}]}}
    arm = replay.score_arm(convs, logs)
    assert arm["counts"]["test-EDACC-C1"] == (0, 3)
    assert arm["counts"]["test-EDACC-C2"] == (1, 2)
    assert arm["wer"] == pytest.approx(1 / 5)
    assert arm["left_parakeet"] == ["test-EDACC-C2"]
    assert arm["fallback_reasons"] == {"noWordsFromSpeech": 1}
    assert arm["word_lag_p50"] == pytest.approx(0.6)


def test_score_arm_refuses_a_missing_session():
    convs = [{"id": "x", "reference": "a", "segments": []}]
    with pytest.raises(ValueError, match="missing"):
        replay.score_arm(convs, {})


def test_engine_only_text_joins_the_same_clips_from_the_results_file():
    convs = [{"id": "test-EDACC-C1", "reference": "a b",
              "segments": [{"clip_id": "test-EDACC-C1-1"}, {"clip_id": "test-EDACC-C1-2"}]}]
    rows = [{"clip_id": "test-EDACC-C1-1", "engine": "parakeet-fluidaudio", "model": "ultra-pal6", "repeat": 1, "hypothesis": "A"},
            {"clip_id": "test-EDACC-C1-2", "engine": "parakeet-fluidaudio", "model": "ultra-pal6", "repeat": 1, "hypothesis": "B"},
            {"clip_id": "test-EDACC-C1-2", "engine": "parakeet-fluidaudio", "model": "ultra-pal6", "repeat": 2, "hypothesis": "X"},
            {"clip_id": "test-EDACC-C1-1", "engine": "apple-speechanalyzer", "model": "SpeechTranscriber en-US", "repeat": 1, "hypothesis": "Z"}]
    logs = replay.engine_only_logs(convs, rows, engine="parakeet-fluidaudio", model="ultra-pal6")
    assert replay.session_text(logs["test-EDACC-C1"]) == "A B"   # repeat 1 only
    with pytest.raises(ValueError, match="no engine-only row"):
        replay.engine_only_logs(convs, rows[:1], engine="parakeet-fluidaudio", model="ultra-pal6")
