"""Streaming greedy transducer decoding for the zipformer, independent of the runtime (#220).

The same loop drives the PyTorch modules (to check the conversion) and the Core ML builds (to score them): an encoder
call per 1.28 s window of fbank frames, then for each of its 32 output frames one joiner call, emitting at most one
token per frame, as sherpa-onnx's greedy search does. Time is O(frames) encoder work plus O(encoder frames) joiner
calls; memory is the model states plus the transcript.
"""
from __future__ import annotations

from typing import Callable, Iterator, Sequence

import numpy as np

CHUNK = 64                  # encoder frames per call (50 Hz): 1.28 s, the shipped sherpa-onnx build's chunk
OUT_FRAMES = CHUNK // 2     # frames out per call: the encoder downsamples once more, to 25 Hz (40 ms each)
PAD = 7 + 2 * 3             # fbank frames the convolutional front end needs beyond 2 * CHUNK
WINDOW = CHUNK * 2 + PAD    # 141 fbank frames in per encoder call (the export's "T")
SHIFT = CHUNK * 2           # 128 fbank frames (1.28 s at 100 Hz) consumed per call ("decode_chunk_len")
CONTEXT_SIZE = 2            # decoder context, in tokens

BLANK = 0
SR = 16000


def windows(num_frames: int) -> Iterator[tuple[int, int]]:
    """(start, end) of each full WINDOW-frame encoder input, SHIFT frames apart. A partial tail window is dropped:
    callers pad the audio with trailing silence first, as the #217 harness does for sherpa-onnx."""
    start = 0
    while start + WINDOW <= num_frames:
        yield start, start + WINDOW
        start += SHIFT


def greedy(frames: np.ndarray, encode: Callable, decode: Callable, join: Callable, init_states: Sequence,
           on_chunk: Callable[[int, list[int]], None] | None = None,
           on_token: Callable[[int, int], None] | None = None) -> list[int]:
    """frames (T, 80) fbank → token ids. encode(window (1, WINDOW, 80), states) → (out (1, OUT_FRAMES, D), states);
    decode(context (1, CONTEXT_SIZE) int32) → (1, D); join(enc (1, D), dec (1, D)) → (1, vocab).
    The context starts as [-1, blank], icefall's convention (-1 is "no token" and embeds to zero).
    on_chunk(chunk_index, tokens_so_far) is called after each chunk and on_token(chunk_index, frame) after each
    emitted token, for latency measurement."""
    tokens: list[int] = []
    context = np.array([[-1] * (CONTEXT_SIZE - 1) + [BLANK]], dtype=np.int32)
    dec = decode(context)
    states = list(init_states)
    for i, (a, b) in enumerate(windows(len(frames))):
        out, states = encode(frames[None, a:b, :].astype(np.float32), states)
        out = np.asarray(out)
        if out.shape[1] != OUT_FRAMES:
            raise ValueError(f"encoder returned {out.shape[1]} frames, expected {OUT_FRAMES}")
        for t in range(OUT_FRAMES):
            k = int(np.argmax(np.asarray(join(out[:, t, :], dec))[0]))
            if k != BLANK:
                tokens.append(k)
                if on_token:
                    on_token(i, t)
                context = np.array([[*context[0, 1:], k]], dtype=np.int32)
                dec = decode(context)
        if on_chunk:
            on_chunk(i, tokens)
    return tokens


def read_tokens(path) -> dict[int, str]:
    """sherpa-onnx tokens.txt: '<symbol> <id>' per line."""
    table = {}
    for line in open(path, encoding="utf-8"):
        parts = line.rstrip("\n").rsplit(" ", 1)
        if len(parts) == 2:
            table[int(parts[1])] = parts[0]
    return table


def to_text(tokens: Sequence[int], table: dict[int, str]) -> str:
    """SentencePiece pieces → text: '▁' starts a word. Unknown ids are skipped rather than guessed."""
    return "".join(table.get(t, "") for t in tokens).replace("▁", " ").strip()


def fbank(samples: np.ndarray) -> np.ndarray:
    """80-bin Kaldi fbank as icefall trained it (lhotse Fbank; sherpa-onnx's defaults): 25 ms / 10 ms frames, povey
    window, no dither, snip_edges false, 20 Hz to Nyquist − 400 Hz, samples in [−1, 1]. Returns (T, 80) float32."""
    import torch
    import torchaudio.compliance.kaldi as kaldi
    wave = torch.from_numpy(np.ascontiguousarray(samples, dtype=np.float32))[None]
    feats = kaldi.fbank(wave, num_mel_bins=80, sample_frequency=SR, frame_length=25.0, frame_shift=10.0,
                        dither=0.0, snip_edges=False, low_freq=20.0, high_freq=-400.0, energy_floor=1e-10)
    return feats.numpy().astype(np.float32)


def pad_for_streaming(samples: np.ndarray) -> np.ndarray:
    """Two chunks and half a second of trailing silence, the #217 harness's padding, so the last words are emitted."""
    return np.concatenate([samples, np.zeros(int(2 * SHIFT / 100 * SR) + SR // 2, dtype=np.float32)])
