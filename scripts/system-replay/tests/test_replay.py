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


def test_by_fallback_splits_an_arm_by_its_own_engine_record_and_pairs_each_part():
    # arm B left Parakeet on C2 only; the split must follow that record, and each part pairs with the reference arm
    # on exactly those conversations (a conversation is never in both parts, none is dropped).
    results = {"A": {"counts": {"C1": (1, 10), "C2": (2, 10), "C3": (3, 10)}, "left_parakeet": []},
               "B": {"counts": {"C1": (0, 10), "C2": (5, 10), "C3": (1, 10)}, "left_parakeet": ["C2"]}}
    split = replay.by_fallback(results, "B", ["A"], n_boot=200)
    stayed, left = split["A"]["stayed on Parakeet"], split["A"]["left Parakeet"]
    assert stayed["units"] == 2 and left["units"] == 1
    assert stayed["gap"] == pytest.approx((1 / 20) - (4 / 20))
    assert left["gap"] == pytest.approx(0.5 - 0.2)


def test_by_fallback_is_empty_for_an_arm_that_never_left_parakeet():
    results = {"A": {"counts": {"C1": (1, 10)}, "left_parakeet": []},
               "B": {"counts": {"C1": (0, 10)}, "left_parakeet": []}}
    assert replay.by_fallback(results, "B", ["A"]) == {}


# --- noise mixing -----------------------------------------------------------------------------------------------

def _read(path: Path) -> list[int]:
    with wave.open(str(path)) as w:
        raw = w.readframes(w.getnframes())
    return list(struct.unpack(f"<{len(raw) // 2}h", raw))


def _power(xs: list[int]) -> float:
    return sum(x * x for x in xs) / len(xs)


def _mix_fixture(tmp_path: Path, noise_seconds: float = 3.0):
    src, noise = tmp_path / "src", tmp_path / "noise"
    src.mkdir(); noise.mkdir()
    rate = 16_000
    # speech 0-1 s and 2-3 s, digital silence between and after: the stitcher's shape
    tone = [int(8000 * math.sin(2 * math.pi * 220 * i / rate)) for i in range(rate)]
    write_wav(src / "test-EDACC-C1.16k.wav", tone + [0] * rate + tone + [0] * rate)
    write_wav(src / "test-EDACC-C2.16k.wav", tone + [0] * rate)
    import random as _r
    g = _r.Random(1)
    for env in ("PRESTO", "TCAR"):
        write_wav(noise / f"{env}.wav", [int(g.gauss(0, 3000)) for _ in range(int(noise_seconds * rate))])
    convs = [{"id": "test-EDACC-C1", "file16k": "test-EDACC-C1.16k.wav", "file": "test-EDACC-C1.48k.wav",
              "reference": "a b", "audio_seconds": 4.0,
              "segments": [{"clip_id": "x-1", "start": 0.0, "end": 1.0}, {"clip_id": "x-2", "start": 2.0, "end": 3.0}]},
             {"id": "test-EDACC-C2", "file16k": "test-EDACC-C2.16k.wav", "file": "test-EDACC-C2.48k.wav",
              "reference": "c", "audio_seconds": 2.0, "segments": [{"clip_id": "y-1", "start": 0.0, "end": 1.0}]}]
    (src / "conversations-test.jsonl").write_text("".join(json.dumps(c) + "\n" for c in convs))
    return src, noise, tone


def test_mix_hits_the_snr_on_the_speech_and_fills_the_gaps_with_noise(tmp_path):
    src, noise, tone = _mix_fixture(tmp_path)
    out = tmp_path / "out"
    convs = replay.mix(src / "conversations-test.jsonl", noise, ["PRESTO", "TCAR"], out, snr_db=5.0, split="test")
    mixed = _read(out / "test-EDACC-C1.16k.wav")
    clean = _read(src / "test-EDACC-C1.16k.wav")
    added = [m - c for m, c in zip(mixed, clean)]
    speech = [x for i, x in enumerate(clean) if i < 16_000 or 32_000 <= i < 48_000]
    speech_noise = [x for i, x in enumerate(added) if i < 16_000 or 32_000 <= i < 48_000]
    assert 10 * math.log10(_power(speech) / _power(speech_noise)) == pytest.approx(5.0, abs=0.3)
    assert _power(mixed[16_000:32_000]) > 0          # the gap is a room now, not digital silence
    assert len(mixed) == len(clean)
    c = convs[0]
    assert c["noise"]["env"] in ("PRESTO", "TCAR") and c["noise"]["snr_db"] == 5.0
    assert c["reference"] == "a b" and c["segments"][1]["start"] == 2.0   # scoring inputs untouched
    assert (out / "conversations-test.jsonl").exists()


def test_mix_is_deterministic_and_loops_noise_shorter_than_the_recording(tmp_path):
    src, noise, _ = _mix_fixture(tmp_path, noise_seconds=1.5)   # shorter than C1's 4 s
    a = replay.mix(src / "conversations-test.jsonl", noise, ["PRESTO", "TCAR"], tmp_path / "a", snr_db=0.0, split="test")
    b = replay.mix(src / "conversations-test.jsonl", noise, ["PRESTO", "TCAR"], tmp_path / "b", snr_db=0.0, split="test")
    assert [c["noise"] for c in a] == [c["noise"] for c in b]
    assert _read(tmp_path / "a" / "test-EDACC-C1.16k.wav") == _read(tmp_path / "b" / "test-EDACC-C1.16k.wav")
    assert _power(_read(tmp_path / "a" / "test-EDACC-C1.16k.wav")[-8000:]) > 0   # noise still there at the end


def test_mix_environment_depends_only_on_the_conversation_id():
    envs = ["PRESTO", "PCAFETER", "DLIVING", "TCAR"]
    picks = {replay.noise_env(f"test-EDACC-C{i}", envs) for i in range(40)}
    assert picks == set(envs)                                    # all used over 40 conversations
    assert replay.noise_env("test-EDACC-C7", envs) == replay.noise_env("test-EDACC-C7", list(envs))
