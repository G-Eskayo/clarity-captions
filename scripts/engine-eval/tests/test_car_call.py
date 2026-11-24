"""Car-call test set (#303): the generator and the per-voice scorer. Each test tries to break one promise the
results table depends on: the call really is narrowband, the SNR really is what the table says, the near talker
really is louder, the references really are the source's, and a seed really reproduces the set."""
from __future__ import annotations

import json
import shutil
import wave

import numpy as np
import pytest

from car_call import chain, score
from car_call.build import Pair, build_set, select_pairs

SR = 16000


def _speechlike(seconds: float, seed: int) -> np.ndarray:
    """Full-band test signal: white noise with syllable-rate bursts, energy right up to 8 kHz."""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    env = 0.5 + 0.5 * np.sin(2 * np.pi * 4.0 * np.arange(n) / SR) ** 2
    return (0.2 * rng.standard_normal(n) * env).astype(np.float32)


def _band_fraction(x: np.ndarray, lo: float, hi: float) -> float:
    spec = np.abs(np.fft.rfft(x.astype(np.float64))) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return float(spec[(f >= lo) & (f < hi)].sum() / spec.sum())


def _db(p: float) -> float:
    return 10 * np.log10(p)


# --- telephone band -------------------------------------------------------------------------------------------

@pytest.mark.parametrize("codec", ["mulaw", "none"])
def test_telephone_band_removes_energy_above_4k(codec):
    x = _speechlike(3.0, 1)
    assert _band_fraction(x, 4000, 8000) > 0.4  # the input really is full band, so the test can fail
    y = chain.telephone(x, SR, codec=codec)
    assert len(y) == len(x)
    # Codec noise is white within 0-4 kHz; nothing above 4 kHz survives the 8 kHz path (> 40 dB down).
    assert _band_fraction(y, 4000, 8000) < 1e-4


def test_telephone_band_kills_a_pure_tone_above_the_band_and_keeps_one_inside():
    t = np.arange(2 * SR) / SR
    inside = (0.3 * np.sin(2 * np.pi * 1000 * t)).astype(np.float32)
    above = (0.3 * np.sin(2 * np.pi * 5000 * t)).astype(np.float32)
    low = (0.3 * np.sin(2 * np.pi * 100 * t)).astype(np.float32)
    y_in, y_above, y_low = (chain.telephone(s, SR, codec="mulaw") for s in (inside, above, low))
    assert _db(np.mean(y_in ** 2) / np.mean(inside ** 2)) > -2      # passband: within 2 dB
    assert _db(np.mean(y_above ** 2) / np.mean(above ** 2)) < -40   # 5 kHz: gone
    assert _db(np.mean(y_low ** 2) / np.mean(low ** 2)) < -12       # 100 Hz: under the 300 Hz edge


def test_codec_actually_changes_the_signal():
    x = _speechlike(1.0, 2)
    assert not np.allclose(chain.telephone(x, SR, codec="mulaw"), chain.telephone(x, SR, codec="none"))


def test_unknown_codec_is_refused():
    with pytest.raises(ValueError):
        chain.telephone(_speechlike(0.5, 3), SR, codec="opus-hd")


def test_best_codec_prefers_amr_only_when_ffmpeg_has_it(monkeypatch):
    monkeypatch.setattr(chain, "_ffmpeg_encoders", lambda: "A..... pcm_mulaw  PCM mu-law")
    assert chain.best_codec() == "mulaw"
    monkeypatch.setattr(chain, "_ffmpeg_encoders", lambda: "A..... libopencore_amrnb  AMR-NB\nA..... pcm_mulaw")
    assert chain.best_codec() == "amrnb"


# --- road noise, speaker and cabin ---------------------------------------------------------------------------

def test_road_noise_is_low_heavy_and_deterministic():
    a = chain.road_noise(4 * SR, SR, np.random.default_rng(7))
    b = chain.road_noise(4 * SR, SR, np.random.default_rng(7))
    c = chain.road_noise(4 * SR, SR, np.random.default_rng(8))
    assert np.array_equal(a, b) and not np.allclose(a, c)
    assert _band_fraction(a, 0, 500) > 0.7         # rumble: most energy under 500 Hz
    assert _band_fraction(a, 300, 3400) > 0.02     # but some of it lands in the call band, where it hurts
    assert np.all(np.isfinite(a)) and len(a) == 4 * SR


def test_road_noise_is_modulated_not_flat():
    a = chain.road_noise(8 * SR, SR, np.random.default_rng(9))
    frames = a[: len(a) // 1600 * 1600].reshape(-1, 1600)
    levels = _db(np.mean(frames ** 2, axis=1))
    assert levels.max() - levels.min() > 2.0


def test_cabin_ir_is_short_and_decays():
    ir = chain.cabin_ir(SR, np.random.default_rng(1), rt60=0.12)
    assert len(ir) <= int(0.25 * SR)
    energy = ir ** 2
    first, last = energy[: len(ir) // 4].sum(), energy[-len(ir) // 4:].sum()
    assert last < first * 1e-2


def test_car_speaker_takes_out_deep_bass_and_keeps_length():
    t = np.arange(SR) / SR
    bass = (0.3 * np.sin(2 * np.pi * 60 * t)).astype(np.float32)
    y = chain.car_speaker(bass, SR)
    assert len(y) == len(bass)
    assert _db(np.mean(y[SR // 4:] ** 2) / np.mean(bass ** 2)) < -6


# --- the mix ------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("snr", [20.0, 10.0, 5.0, 0.0, -5.0])
def test_mix_hits_the_target_snr_within_half_a_db(snr):
    rng = np.random.default_rng(11)
    far = _speechlike(5.0, 4)
    near = _speechlike(3.0, 5)
    m = chain.mix_scene(far, near, SR, rng, snr_db=snr, near_gain_db=6.0, gap_s=0.4)
    # Measure SNR independently from the returned stems, over the far voice's span only.
    s0, s1 = m.far_span
    measured = _db(np.mean(m.far_stem[s0:s1] ** 2) / np.mean(m.noise_stem[s0:s1] ** 2))
    assert abs(measured - snr) <= 0.5
    # The stems really add up to the mix (bar float32 rounding and the final peak guard's gain).
    total = m.far_stem + m.near_stem + m.noise_stem
    assert np.allclose(m.mix, total * m.gain, atol=1e-5)


def test_near_talker_is_louder_than_the_far_voice():
    rng = np.random.default_rng(12)
    m = chain.mix_scene(_speechlike(5.0, 6), _speechlike(3.0, 7), SR, rng, snr_db=10, near_gain_db=6.0)
    f0, f1 = m.far_span
    n0, n1 = m.near_span
    far_db = _db(np.mean(m.far_stem[f0:f1] ** 2))
    near_db = _db(np.mean(m.near_stem[n0:n1] ** 2))
    assert near_db - far_db == pytest.approx(6.0, abs=0.5)


def test_near_talker_is_full_band_while_far_is_not():
    rng = np.random.default_rng(13)
    m = chain.mix_scene(_speechlike(4.0, 8), _speechlike(4.0, 9), SR, rng, snr_db=10)
    f0, f1 = m.far_span
    n0, n1 = m.near_span
    assert _band_fraction(m.far_stem[f0:f1], 4000, 8000) < 1e-4
    assert _band_fraction(m.near_stem[n0:n1], 4000, 8000) > 0.05


def test_far_and_near_do_not_overlap_and_noise_covers_both():
    rng = np.random.default_rng(14)
    m = chain.mix_scene(_speechlike(2.0, 1), _speechlike(2.0, 2), SR, rng, snr_db=5, gap_s=0.5)
    assert m.far_span[1] <= m.near_span[0]
    assert np.all(m.near_stem[: m.far_span[1]] == 0)
    assert np.mean(m.noise_stem[m.near_span[0]: m.near_span[1]] ** 2) > 0


def test_mix_never_clips():
    rng = np.random.default_rng(15)
    m = chain.mix_scene(_speechlike(2.0, 3) * 4, _speechlike(2.0, 4) * 4, SR, rng, snr_db=-5, near_gain_db=12)
    assert np.max(np.abs(m.mix)) <= 0.99


def test_silent_far_voice_is_refused():
    with pytest.raises(ValueError):
        chain.mix_scene(np.zeros(SR, np.float32), _speechlike(1.0, 1), SR, np.random.default_rng(1), snr_db=10)


# --- set building -------------------------------------------------------------------------------------------

def _write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


def _source(tmp_path, n_conversations=4):
    src = tmp_path / "src"
    (src / "audio").mkdir(parents=True, exist_ok=True)
    rows = []
    k = 0
    for c in range(n_conversations):
        for side in "AB":
            for u in range(3):
                k += 1
                cid = f"test-EDACC-C{c:02d}-{side}{u}"
                secs = 8.0 if u == 0 else 4.0
                _write_wav(src / "audio" / f"{cid}.wav", _speechlike(secs, k))
                rows.append({"clip_id": cid, "speaker": f"EDACC-C{c:02d}-{side}", "accent": "Test",
                             "reference": f"WORD{k} " * (14 if u == 0 else 7) + "DON'T stop",
                             "audio_seconds": secs, "file": f"audio/{cid}.wav"})
    with open(src / "manifest.jsonl", "w") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")
    return src, rows


def test_select_pairs_never_pairs_a_conversation_with_itself_and_is_seeded(tmp_path):
    _, rows = _source(tmp_path)
    a = select_pairs(rows, n=3, seed=1, far_seconds=(6, 15), near_seconds=(2, 7), min_far_words=12,
                     min_near_words=6)
    b = select_pairs(rows, n=3, seed=1, far_seconds=(6, 15), near_seconds=(2, 7), min_far_words=12,
                     min_near_words=6)
    assert a == b and len(a) == 3
    for p in a:
        assert score.conversation(p.far["speaker"]) != score.conversation(p.near["speaker"])
    assert len({p.far["speaker"] for p in a}) == 3  # one far clip per speaker


def test_select_pairs_never_uses_a_clip_twice_even_when_windows_overlap(tmp_path):
    _, rows = _source(tmp_path)
    for r in rows:  # every clip qualifies as both far and near
        r["audio_seconds"] = 6.5
        r["reference"] = "WORD " * 14
    pairs = select_pairs(rows, n=4, seed=2, far_seconds=(6, 15), near_seconds=(2, 7), min_far_words=12,
                         min_near_words=6)
    ids = [c["clip_id"] for p in pairs for c in (p.far, p.near)]
    assert len(ids) == len(set(ids))


def test_select_pairs_says_when_there_are_not_enough_clips(tmp_path):
    _, rows = _source(tmp_path, n_conversations=1)
    with pytest.raises(ValueError):
        select_pairs(rows, n=5, seed=1, far_seconds=(6, 15), near_seconds=(2, 7), min_far_words=12,
                     min_near_words=6)


def _build(tmp_path, out_name, seed, select_seed=5):
    src, rows = _source(tmp_path)
    pairs = select_pairs(rows, n=2, seed=select_seed, far_seconds=(6, 15), near_seconds=(2, 7), min_far_words=12,
                         min_near_words=6)
    out = tmp_path / out_name
    build_set(pairs, src, out, snrs=[20, 0], seed=seed, codec="mulaw")
    return out, rows


def test_build_set_is_byte_identical_under_a_seed_and_differs_under_another(tmp_path):
    a, _ = _build(tmp_path, "a", 5)
    b, _ = _build(tmp_path, "b", 5)
    c, _ = _build(tmp_path, "c", 6)
    files_a = sorted(p.relative_to(a) for p in a.rglob("*.wav"))
    assert files_a == sorted(p.relative_to(b) for p in b.rglob("*.wav"))
    for rel in files_a:
        assert (a / rel).read_bytes() == (b / rel).read_bytes(), rel
    assert (a / "manifest.jsonl").read_text() == (b / "manifest.jsonl").read_text()
    # Same clips, another seed: every generated scene changes (new noise, new cabin), the untouched baselines don't.
    assert files_a == sorted(p.relative_to(c) for p in c.rglob("*.wav"))
    for rel in files_a:
        same = (a / rel).read_bytes() == (c / rel).read_bytes()
        assert same == ("clean" in str(rel)), rel


def test_build_set_carries_references_through_unchanged(tmp_path):
    out, rows = _build(tmp_path, "a", 5)
    by_id = {r["clip_id"]: r for r in rows}
    manifest = [json.loads(l) for l in (out / "manifest.jsonl").read_text().splitlines()]
    conditions = {m["condition"] for m in manifest}
    assert conditions == {"clean-far", "clean-near", "phone", "snr20", "snr0"}
    for m in manifest:
        assert (out / m["file"]).exists()
        assert m["far_reference"] == (by_id[m["far_clip"]]["reference"] if m["far_clip"] else "")
        assert m["near_reference"] == (by_id[m["near_clip"]]["reference"] if m["near_clip"] else "")
        # The engine runner's reference is both voices in the order they're heard.
        assert m["reference"] == " ".join(x for x in (m["far_reference"], m["near_reference"]) if x)
        assert m["speaker"] and m["clip_id"].endswith(m["condition"])
    clean = [m for m in manifest if m["condition"] == "clean-far"]
    for m in clean:  # the baseline is the untouched source audio
        assert (out / m["file"]).read_bytes() == (tmp_path / "src" / by_id[m["far_clip"]]["file"]).read_bytes()


def test_build_set_writes_16k_mono_16bit(tmp_path):
    out, _ = _build(tmp_path, "a", 5)
    for p in out.rglob("*.wav"):
        with wave.open(str(p)) as w:
            assert (w.getframerate(), w.getnchannels(), w.getsampwidth()) == (SR, 1, 2)


@pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="needs ffmpeg")
def test_build_refuses_a_codec_ffmpeg_lacks(tmp_path, monkeypatch):
    monkeypatch.setattr(chain, "_ffmpeg_encoders", lambda: "pcm_mulaw")
    src, rows = _source(tmp_path)
    pairs = select_pairs(rows, n=1, seed=1, far_seconds=(6, 15), near_seconds=(2, 7), min_far_words=12,
                         min_near_words=6)
    with pytest.raises(RuntimeError):
        build_set(pairs, src, tmp_path / "x", snrs=[10], seed=1, codec="amrnb")


# --- per-voice scoring ----------------------------------------------------------------------------------------

def test_split_counts_charges_each_voice_its_own_errors():
    far, near = "the cat sat on the mat", "pass the salt please"
    perfect = score.split_counts(far, near, "the cat sat on the mat pass the salt please")
    assert (perfect["far"].errors, perfect["near"].errors) == (0, 0)
    assert (perfect["far"].n, perfect["near"].n) == (6, 4)
    lost_far = score.split_counts(far, near, "pass the salt please")
    assert (lost_far["far"].dele, lost_far["near"].errors) == (6, 0)
    lost_near = score.split_counts(far, near, "the cat sat on the mat")
    assert (lost_near["far"].errors, lost_near["near"].dele) == (0, 4)
    garbled = score.split_counts(far, near, "the bat sat on the mat so pass the salt please")
    assert garbled["far"].sub == 1 and garbled["near"].errors == 0
    assert garbled["far"].ins + garbled["near"].ins == 1


def test_split_counts_with_one_voice_matches_plain_wer():
    from edacc_eval.wer import align_counts
    ref, hyp = "one two three four five", "one too three five six"
    c = score.split_counts(ref, "", hyp)
    assert c["far"].errors == align_counts(ref, hyp).errors and c["near"].n == 0


def test_split_counts_empty_hypothesis_is_all_deletions():
    c = score.split_counts("a b c", "d e", "")
    assert (c["far"].dele, c["near"].dele) == (3, 2)


def test_conversation_id():
    assert score.conversation("EDACC-C55-B") == "EDACC-C55"
    assert score.conversation("EDACC-C06-A") == "EDACC-C06"


def test_score_table_pools_per_engine_condition_and_voice(tmp_path):
    manifest = [
        {"clip_id": "p1-snr0", "condition": "snr0", "speaker": "S1", "far_reference": "the cat sat",
         "near_reference": "pass the salt", "far_clip": "a", "near_clip": "b"},
        {"clip_id": "p1-clean-far", "condition": "clean-far", "speaker": "S1", "far_reference": "the cat sat",
         "near_reference": "", "far_clip": "a", "near_clip": None},
    ]
    results = [
        {"clip_id": "p1-snr0", "engine": "parakeet-fluidaudio", "model": "parakeet-ultra-coreml", "repeat": 1,
         "hypothesis": "the hat sat pass the salt"},
        {"clip_id": "p1-clean-far", "engine": "parakeet-fluidaudio", "model": "parakeet-ultra-coreml",
         "repeat": 1, "hypothesis": "The cat sat."},
    ]
    table = score.score(manifest, results)
    key = ("parakeet-ultra-coreml", "snr0")
    assert table[key]["far"]["wer"] == pytest.approx(1 / 3)
    assert table[key]["near"]["wer"] == 0
    assert table[("parakeet-ultra-coreml", "clean-far")]["far"]["wer"] == 0
    assert "near" not in table[("parakeet-ultra-coreml", "clean-far")]
