"""The zipformer's Core ML path (#220), the parts with no Core ML in them: the streaming greedy decoder against fakes,
token latency, and the owner's rule for recommending a build. The translator is in test_zipformer_coreml.py."""

import numpy as np
import pytest

from zipformer_coreml import decode as zd


# --- decoding ---------------------------------------------------------------------------------------------------------

def test_windows_are_141_frames_128_apart_and_drop_a_partial_tail():
    assert list(zd.windows(140)) == []
    assert list(zd.windows(141)) == [(0, 141)]
    assert list(zd.windows(141 + 127)) == [(0, 141)]
    assert list(zd.windows(141 + 128)) == [(0, 141), (128, 269)]


def test_padding_adds_two_chunks_and_half_a_second_like_the_217_harness():
    out = zd.pad_for_streaming(np.ones(1000, np.float32))
    assert len(out) == 1000 + int(2 * 1.28 * 16000) + 8000
    assert np.all(out[1000:] == 0)


class FakeModel:
    """An encoder whose frame t of chunk c carries a scripted token; the joiner reads it back unless the decoder
    context already ends with it, so a scripted repeat is emitted only once per frame."""

    def __init__(self, script):
        self.script = script  # chunk index → {frame: token}
        self.contexts = []
        self.calls = 0

    def encode(self, window, states):
        assert window.shape == (1, zd.WINDOW, 80)
        out = np.zeros((1, zd.OUT_FRAMES, 4), np.float32)
        for t, k in self.script.get(self.calls, {}).items():
            out[0, t, 0] = k
        self.calls += 1
        return out, [s + 1 for s in states]

    def decode(self, context):
        self.contexts.append(context.tolist())
        return np.array([[float(context[0, -1])]], np.float32)

    def join(self, enc, dec):
        logits = np.zeros((1, 10), np.float32)
        logits[0, int(enc[0, 0])] = 1.0
        return logits


def test_greedy_emits_one_token_per_frame_and_shifts_the_context():
    fake = FakeModel({0: {3: 5, 10: 7}, 1: {0: 5}})
    frames = np.zeros((141 + 128, 80), np.float32)
    seen, emitted = [], []
    toks = zd.greedy(frames, fake.encode, fake.decode, fake.join, [0], on_chunk=lambda i, t: seen.append((i, list(t))),
                     on_token=lambda i, t: emitted.append((i, t)))
    assert toks == [5, 7, 5]
    assert fake.contexts == [[[-1, 0]], [[0, 5]], [[5, 7]], [[7, 5]]]
    assert seen == [(0, [5, 7]), (1, [5, 7, 5])]
    assert emitted == [(0, 3), (0, 10), (1, 0)]


def test_greedy_rejects_an_encoder_with_the_wrong_chunk_length():
    def encode(w, s):
        return np.zeros((1, 64, 4), np.float32), s
    with pytest.raises(ValueError, match="expected 32"):
        zd.greedy(np.zeros((141, 80), np.float32), encode, lambda c: np.zeros((1, 4)), lambda e, d: np.zeros((1, 3)),
                  [])


def test_tokens_to_text_joins_pieces_and_skips_unknown_ids(tmp_path):
    p = tmp_path / "tokens.txt"
    p.write_text("<blk> 0\n▁של 1\nום 2\n▁שלום 3\n", encoding="utf-8")
    table = zd.read_tokens(p)
    assert zd.to_text([3, 1, 2, 99], table) == "שלום שלום"


def test_token_latency_is_the_wait_to_the_chunk_end_plus_that_chunks_compute():
    from zipformer_coreml.run import token_latencies
    events = [("tok", 0, 0), ("tok", 0, 31), (0, 0.05, 2), ("tok", 1, 15), (1, 0.03, 3)]
    lat, compute = token_latencies(events)
    assert compute == [0.05, 0.03]
    np.testing.assert_allclose(lat, [1.28 - 0.04 + 0.05, 0.0 + 0.05, 1.28 - 0.64 + 0.03])


# --- the recommendation rule ------------------------------------------------------------------------------------------

def _cell(cer, lo, hi):
    from edacc_eval.report_hebrew import HebrewCell, Rate
    r = Rate(cer, lo, hi)
    return HebrewCell(wer=r, cer=r, lenient_wer=r, lenient_cer=r, words=1, chars=1, sub=0, dele=0, ins=0, clips=1,
                      groups=1, audio_seconds=1, processing_seconds=1)


def _scores(**variants):
    from zipformer_coreml.report import APPLE, SHERPA_INT8, SETS
    from zipformer_coreml.run import model_name
    base = {SHERPA_INT8: _cell(0.025, 0.021, 0.028), APPLE: _cell(0.104, 0.078, 0.133)}
    return {s: {**base, **{model_name(v): _cell(*c) for v, c in variants.items()}} for s in SETS}


def test_the_smallest_build_overlapping_int8_and_far_from_apple_is_recommended():
    from zipformer_coreml.report import choose
    scores = _scores(fp16=(0.025, 0.021, 0.028), pal4=(0.027, 0.023, 0.031), pal3=(0.031, 0.029, 0.035),
                     pal2=(0.20, 0.15, 0.25))
    sizes = {"fp16": 135e6, "pal4": 35e6, "pal3": 27e6, "pal2": 19e6}
    # pal2 is far worse than int8; pal3's interval starts above int8's; pal4 overlaps.
    assert choose(scores, sizes) == "pal4"


def test_overlap_alone_is_not_enough_if_the_build_is_not_well_clear_of_apple():
    from edacc_eval.report_hebrew import Rate  # noqa: F401
    from zipformer_coreml.report import choose
    from zipformer_coreml.run import model_name
    scores = _scores(pal3=(0.026, 0.020, 0.080), fp16=(0.025, 0.021, 0.028))
    # pal3's interval overlaps int8's but its upper bound reaches Apple's interval
    assert choose(scores, {"pal3": 27e6, "fp16": 135e6}) == "fp16"
    del scores["eval-whatsapp"][model_name("fp16")]
    assert choose(scores, {"pal3": 27e6, "fp16": 135e6}) is None  # a build must be scored on both sets
