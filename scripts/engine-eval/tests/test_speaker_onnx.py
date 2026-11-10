"""#160: tests that try to break the Python port of the app's live speaker path (CaptionCore SpeakerLabelSmoother,
SpeakerAligner, SpeakerPathReplay) and of FluidAudio's Sortformer streaming host (mel, chunking, state update,
timeline), which drive the ONNX engines on the #276 scoreboard.

The smoother and aligner cases are the Swift tests (SpeakerLabelSmootherTests, SpeakerAlignerTests) case for case:
the port has to give the screen the same labels as the app, or the scoreboard compares ports, not engines.
"""
import json
import math

import numpy as np
import pytest

from speaker_onnx.live_path import LabelSmoother, Seg, aligner_speaker, is_stream, replay
from speaker_onnx.sortformer import (Config, MelFrontend, StateUpdater, StreamingSortformer, Timeline,
                                     available_mel_frames)


def seg(s, a, b):
    return Seg(s, a, b)


# ---- SpeakerLabelSmoother (SpeakerLabelSmootherTests.swift) ------------------------------------------------------

def test_no_segments_means_no_label_yet():
    assert LabelSmoother().label(0, 2, [], False) is None


def test_one_voice_stays_one_speaker():
    s = LabelSmoother()
    segs = [seg(0, 0, 4), seg(0, 4.3, 9)]
    assert s.label(0, 2, segs, False) == 0
    assert s.label(0, 4, segs, True) == 0
    assert s.label(4.3, 9, segs, True) == 0


def test_a_laugh_length_blip_of_another_slot_does_not_change_the_speaker():
    s = LabelSmoother()
    segs = [seg(0, 0, 2.0), seg(1, 2.0, 2.3), seg(0, 2.3, 6)]
    assert s.label(0, 1.8, segs, False) == 0
    assert s.label(1.9, 2.4, segs, False) == 0
    assert s.label(0, 6, segs, True) == 0


def test_a_short_pitch_change_mid_sentence_keeps_the_current_speaker_while_live():
    s = LabelSmoother()
    assert s.label(0, 3, [seg(0, 0, 3)], True) == 0
    assert s.label(3.4, 4.0, [seg(0, 0, 3), seg(0, 3.4, 4.0)], False) == 0
    assert s.label(3.4, 4.7, [seg(0, 0, 3), seg(0, 3.4, 4.0), seg(1, 4.0, 4.7)], False) == 0


def known_pair():
    s = LabelSmoother()
    history = [seg(0, 0, 3), seg(1, 3.5, 6.5)]
    s.label(0, 3, history, True)
    s.label(3.5, 6.5, history, True)
    s.label(7, 9, history + [seg(0, 7, 9)], True)
    return s, history + [seg(0, 7, 9)]


def test_a_blip_of_a_known_voice_does_not_take_a_short_caption():
    s, h = known_pair()
    assert s.label(10.0, 10.4, h + [seg(0, 9.3, 10.0), seg(1, 10.0, 10.3), seg(0, 10.3, 14)], True) == 0


def test_a_live_result_needs_a_second_of_the_other_voice_before_switching():
    s, h = known_pair()
    assert s.label(9.3, 9.9, h + [seg(0, 9.3, 9.9)], False) == 0
    assert s.label(9.3, 10.6, h + [seg(0, 9.3, 9.9), seg(1, 9.9, 10.6)], False) == 0
    assert s.label(9.3, 11.2, h + [seg(0, 9.3, 9.9), seg(1, 9.9, 11.2)], False) == 1


def test_a_new_utterance_of_a_known_voice_is_labeled_at_once():
    s, h = known_pair()
    assert s.label(9.6, 10.3, h + [seg(1, 9.6, 10.3)], False) == 1


def test_a_real_turn_is_shown_and_numbered_in_order_of_appearance():
    s = LabelSmoother()
    segs = [seg(2, 0, 4), seg(0, 4.5, 8.5)]
    assert s.label(0, 4, segs, True) == 0
    assert s.label(4.5, 8.5, segs, True) == 1
    assert s.label(9, 10, segs + [seg(2, 9, 10.5)], True) == 0


def test_rapid_back_and_forth_still_alternates():
    s, segs, shown = LabelSmoother(), [], []
    for i in range(6):
        st = i * 1.7
        segs.append(seg(i % 2, st, st + 1.5))
        shown.append(s.label(st, st + 1.5, segs, True))
    assert shown == [0, 1, 0, 1, 0, 1]


def test_a_short_real_reply_is_still_its_own_speaker():
    s = LabelSmoother()
    assert s.label(0, 4, [seg(0, 0, 4), seg(1, 4.6, 5.0), seg(0, 5.4, 9)], True) == 0
    w = LabelSmoother()
    earlier = [seg(1, 0, 3), seg(0, 3.5, 7), seg(1, 7.6, 8.0)]
    assert w.label(0, 3, earlier, True) == 0
    assert w.label(3.5, 7, earlier, True) == 1
    assert w.label(7.6, 8.0, earlier, True) == 0


def test_an_interruption_goes_to_whoever_says_most_of_the_caption():
    s = LabelSmoother()
    assert s.label(0, 3, [seg(0, 0, 3), seg(1, 10, 12)], True) == 0
    assert s.label(12.5, 16, [seg(0, 0, 3), seg(1, 10, 12), seg(0, 12.5, 13.5), seg(1, 13.5, 16)], True) == 1


def test_a_new_persons_first_short_utterance_is_theirs_at_once():
    s = LabelSmoother()
    assert s.label(0, 4, [seg(0, 0, 4)], True) == 0
    assert s.label(4.5, 5.3, [seg(0, 0, 4), seg(2, 4.5, 5.3)], False) == 1


def test_a_live_scrap_of_an_unseen_slot_does_not_take_a_number():
    s = LabelSmoother()
    assert s.label(0, 3, [seg(0, 0, 3)], True) == 0
    scrap = [seg(0, 0, 3), seg(1, 3.2, 3.36)]
    assert s.label(3.2, 3.4, scrap, False) is None
    assert s.label(3.2, 6.4, scrap + [seg(2, 3.36, 6.4)], False) == 1
    f = LabelSmoother()
    assert f.label(0, 3, [seg(0, 0, 3)], True) == 0
    assert f.label(3.2, 3.4, scrap, True) == 1


def test_a_new_voice_after_a_long_silence_is_a_new_speaker():
    s = LabelSmoother()
    segs = [seg(0, 0, 5), seg(1, 30, 34)]
    assert s.label(0, 5, segs, True) == 0
    assert s.label(30, 34, segs, True) == 1


def test_the_first_caption_of_a_session_takes_whatever_slot_it_has():
    assert LabelSmoother().label(0, 0.6, [seg(3, 0, 0.6)], False) == 0


def test_a_zero_length_caption_uses_the_segment_containing_it():
    assert LabelSmoother().label(2, 2, [seg(1, 0, 5)], False) == 0


def test_an_exact_tie_is_broken_the_same_way_every_run():
    # Swift breaks this with random dictionary order (#275). The port must be deterministic: the lower slot wins
    # unless the current speaker is one of the tied slots.
    segs = [seg(3, 0, 1), seg(1, 1, 2)]
    assert {LabelSmoother().label(0, 2, segs, True) for _ in range(20)} == {0}
    s = LabelSmoother()
    s.label(0, 1, [seg(3, 0, 1)], True)
    assert s.label(0, 2, segs, True) == 0  # current slot 3 holds the tie, keeps it (shown as 0)


# ---- SpeakerAligner (SpeakerAlignerTests.swift) ------------------------------------------------------------------

def test_aligner_picks_the_largest_overlap_and_sums_a_speakers_segments():
    assert aligner_speaker(1.5, 5.0, [seg(0, 0, 2), seg(1, 2, 5)]) == 1
    assert aligner_speaker(0, 4, [seg(0, 0, 1), seg(1, 1, 2.5), seg(0, 2.5, 4)]) == 0


def test_aligner_without_overlap_has_no_speaker_but_a_point_falls_back_to_its_segment():
    assert aligner_speaker(0, 1, []) is None
    assert aligner_speaker(10, 11, [seg(0, 0, 2)]) is None
    assert aligner_speaker(3.0, 3.0, [seg(0, 0, 2), seg(1, 2, 5)]) == 1


# ---- the replay schedule (SpeakerPathReplay.swift) ---------------------------------------------------------------

class FakeDiarizer:
    """Speaks one slot per phrase as soon as the audio for it has been fed."""

    def __init__(self, truth):
        self.truth, self.fed, self.finished = truth, 0.0, False

    def feed(self, samples):
        self.fed += len(samples) / 16000

    @property
    def segments(self):
        return [Seg(s, a, min(b, self.fed)) for s, a, b in self.truth if a < self.fed]

    def finish(self):
        self.finished = True


def run_fake(phrases, truth, seconds):
    audio = np.zeros(int(seconds * 16000), np.float32)
    d = FakeDiarizer(truth)
    return replay(d, iter([audio[i:i + 5000] for i in range(0, len(audio), 5000)]), phrases), d


def test_stream_check_matches_swift():
    assert is_stream([(0, 1), (1, 2.5), (4, 5)]) and is_stream([])
    assert not is_stream([(0, 2), (1.9, 3)])
    assert not is_stream([(3, 4), (0, 1)])
    assert not is_stream([(1, 1)]) and not is_stream([(2, 1)]) and not is_stream([(-0.5, 1)])


def test_replay_refuses_a_non_stream_before_touching_the_diarizer():
    with pytest.raises(ValueError):
        replay(None, iter([]), [(0, 2), (1, 3)])


def test_every_phrase_gets_exactly_one_final_a_second_after_it_ends_even_past_the_audio():
    phrases = [(0.2, 1.5), (2.0, 4.0), (4.0, 4.9)]   # the last ends 0.1 s before the audio does
    r, d = run_fake(phrases, [(0, 0.2, 1.5), (1, 2.0, 4.0), (0, 4.0, 4.9)], 5.0)
    finals = [e for e in r["emissions"] if e["final"]]
    assert [e["phrase"] for e in finals] == [0, 1, 2]
    for e, (a, b) in zip(finals, phrases):
        assert b + 1.0 <= e["now"] < b + 1.0 + 1365 / 16000 + 1e-9
    assert r["audio_seconds"] == pytest.approx(5.0) and d.finished
    assert [e["label"] for e in finals] == [0, 1, 0]


def test_live_results_come_every_half_second_for_the_line_being_spoken_only():
    phrases = [(0.0, 3.0), (5.0, 6.0)]
    r, _ = run_fake(phrases, [(0, 0.0, 3.0), (1, 5.0, 6.0)], 8.0)
    live = [e for e in r["emissions"] if not e["final"]]
    nows = [e["now"] for e in live]
    assert all(b - a >= 0.5 - 1e-9 for a, b in zip(nows, nows[1:]))
    # nothing live while no line is being spoken (3 s + 1 s final delay until 5 s)
    assert not [e for e in live if 4.0 + 0.09 < e["now"] < 5.0]
    # a phrase that already has its final never gets another live result
    final_at = {e["phrase"]: e["now"] for e in r["emissions"] if e["final"]}
    assert all(e["now"] < final_at[e["phrase"]] for e in live)


def test_the_live_label_only_sees_audio_fed_so_far():
    # Slot 1 starts at 2.0; a live result at 1.5 can't know about it.
    r, _ = run_fake([(0.0, 4.0)], [(0, 0.0, 1.9), (1, 2.0, 4.0)], 6.0)
    early = [e for e in r["emissions"] if not e["final"] and e["now"] < 1.9]
    assert early and all(e["raw"] == 0 for e in early)


def test_result_has_what_the_scorer_reads():
    r, _ = run_fake([(0.0, 1.0)], [(2, 0.0, 1.0)], 2.0)
    for k in ("emissions", "segments", "audio_seconds", "wall_seconds", "load_seconds", "chunk_ms", "chunk_audio_ms"):
        assert k in r
    e = r["emissions"][0]
    assert set(e) == {"now", "phrase", "final", "label", "raw"}
    assert r["segments"] == [{"speaker": 2, "start": 0.0, "end": 1.0}]
    json.dumps(r)


# ---- mel (FluidAudio AudioMelSpectrogram, NeMo-style) -----------------------------------------------------------

def test_mel_frame_count_is_the_center_padded_count_and_silence_is_the_log_floor():
    m = MelFrontend()
    x = np.zeros(16000, np.float32)
    f = m(x)
    assert f.shape == (1 + (16000 + 512 - 400) // 160, 128)
    assert np.allclose(f, math.log(2 ** -24))


def test_mel_puts_a_tone_in_the_right_band_and_is_causal_per_frame():
    m = MelFrontend()
    t = np.arange(32000) / 16000
    x = (0.1 * np.sin(2 * np.pi * 1000 * t)).astype(np.float32)
    f = m(x)
    band = int(np.argmax(f[100]))
    hz = m.center_hz[band]
    assert 900 < hz < 1100
    # frame k depends only on samples before k*160+200: changing later audio leaves it alone
    y = x.copy(); y[16000:] = 0
    g = m(y)
    k = (16000 - 200) // 160
    assert np.array_equal(f[:k], g[:k]) and not np.array_equal(f[k + 3], g[k + 3])


def test_mel_availability_gate():
    assert available_mel_frames(199) == 0
    assert available_mel_frames(200) == 1
    assert available_mel_frames(200 + 160) == 2


# ---- streaming chunker + state update + timeline ----------------------------------------------------------------

class ConstModel:
    """Stands in for the ONNX graph: per-frame activity from a schedule, embeddings that record the frame index."""

    def __init__(self, cfg, activity):
        self.cfg, self.activity, self.calls = cfg, activity, []

    def __call__(self, chunk, spkcache, fifo):
        i = len(self.calls)
        self.calls.append((chunk.shape[0], spkcache.shape[0], fifo.shape[0]))
        n = (chunk.shape[0] + 7) // 8
        start = i * self.cfg.chunk_len - (self.cfg.chunk_left_context if i else 0)   # diarizer frame of row 0
        # The real graph re-predicts the cached and queued frames every call; each embedding carries its frame.
        held = [self.activity(int(e[0])) for e in np.vstack([spkcache, fifo])]
        preds = np.array(held + [self.activity(start + k) for k in range(n)], np.float32).reshape(-1, self.cfg.num_speakers)
        embs = np.tile(np.arange(start, start + n, dtype=np.float32)[:, None], (1, 512))
        return preds, embs


def make_stream(activity, cfg=None):
    cfg = cfg or Config()
    model = ConstModel(cfg, activity)
    return StreamingSortformer(model, cfg), model


def test_first_chunk_waits_for_core_plus_right_context_and_has_no_left_context():
    s, model = make_stream(lambda f: [0.9, 0, 0, 0])
    need = (48 + 56 - 1) * 160 + 200          # samples for 104 mel frames
    s.feed(np.zeros(need - 1, np.float32))
    assert model.calls == []
    s.feed(np.zeros(1, np.float32))
    assert model.calls == [(104, 0, 0)]
    s.feed(np.zeros(48 * 160, np.float32))
    assert model.calls[1] == (112, 0, 6)     # left context 1 frame (8 mel), FIFO holds chunk 0's 6 frames


def test_fifo_overflow_moves_31_frames_to_the_speaker_cache_and_cache_never_exceeds_188():
    cfg = Config()
    s, model = make_stream(lambda f: [0.9, 0, 0, 0] if (f // 50) % 2 == 0 else [0, 0.9, 0, 0])
    s.feed(np.zeros(16000 * 60, np.float32))
    sc = [c[1] for c in model.calls]
    ff = [c[2] for c in model.calls]
    assert max(ff) <= cfg.fifo_len and max(sc) <= cfg.spkcache_len
    assert 31 in sc and 188 in sc
    assert sc == sorted(sc)                 # the cache only grows, then holds at 188


def test_compressed_cache_keeps_both_speakers_in_speaker_then_time_order():
    cfg = Config()
    s, _ = make_stream(lambda f: [0.95, 0.01, 0.01, 0.01] if (f // 40) % 2 == 0 else [0.01, 0.95, 0.01, 0.01])
    s.feed(np.zeros(16000 * 90, np.float32))
    st = s.state
    assert st.spkcache.shape == (188, 512)
    frames = st.spkcache[:, 0]
    who = np.argmax(st.spkcache_preds, axis=1)
    real = st.spkcache_preds.max(axis=1) > 0.5
    assert set(who[real]) == {0, 1}
    # speaker-major: all of speaker 0's kept frames come before speaker 1's, each in time order
    order = [(w, f) for w, f, r in zip(who, frames, real) if r]
    assert order == sorted(order)


def test_silence_profile_only_learns_from_silent_frames():
    st = StateUpdater(Config()).new_state()
    up = StateUpdater(Config())
    embs = np.stack([np.full(512, 5.0), np.full(512, 1.0)]).astype(np.float32)
    preds = np.array([[0.9, 0, 0, 0], [0.05, 0.05, 0, 0]], np.float32)
    up.update_silence(st, embs, preds)
    assert st.silence_count == 1 and np.allclose(st.mean_silence, 1.0)


def test_timeline_joins_a_turn_across_chunks_and_keeps_the_open_turn_tentative():
    tl = Timeline(Config())
    on, off = [0.9, 0, 0, 0], [0, 0, 0, 0]
    u1 = tl.add(np.array([off, on, on, on, on, on], np.float32), np.array([on, on], np.float32))
    assert u1.finalized == [] and [(x.speaker, x.start_frame, x.end_frame) for x in u1.tentative] == [(0, 1, 8)]
    u2 = tl.add(np.array([on, on, off, off, off, off], np.float32), np.array([off, off], np.float32))
    assert [(x.speaker, x.start_frame, x.end_frame) for x in u2.finalized] == [(0, 1, 8)]
    assert u2.tentative == []


def test_timeline_threshold_is_strict_on_onset_and_inclusive_on_offset():
    tl = Timeline(Config())
    u = tl.add(np.array([[0.5, 0, 0, 0], [0.51, 0, 0, 0], [0.5, 0, 0, 0], [0.49, 0, 0, 0]], np.float32),
               np.zeros((0, 4), np.float32))
    assert [(x.start_frame, x.end_frame) for x in u.finalized] == [(1, 3)]


def test_live_segments_are_finalized_plus_the_latest_tentative_only():
    s, _ = make_stream(lambda f: [0.9, 0, 0, 0] if f < 30 else [0, 0, 0, 0.9])
    s.feed(np.zeros(16000 * 5, np.float32))
    segs = s.segments
    starts = [(x.speaker, round(x.start, 2)) for x in segs]
    assert (0, 0.0) in starts and any(sp == 3 for sp, _ in starts)
    assert len({(x.speaker, x.start) for x in segs}) == len(segs)   # no stale tentative copies
