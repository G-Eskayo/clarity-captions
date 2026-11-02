"""Writes the fixture CaptionCore's Swift fbank is checked against (#220): torchaudio's Kaldi fbank, with the options
the zipformer was trained with (decode.fbank), of a signal both sides can make exactly.

    python -m zipformer_coreml.fbank_fixture Packages/CaptionCore/Tests/CaptionCoreTests/Fixtures/zipformer-fbank.json

The signal (0.5 s at 16 kHz) is three tones, one fading in, so every frame differs:
    x[n] = 0.3 sin(2π·440·n/16000) + 0.2 sin(2π·1234.5·n/16000) + 0.05·(n/8000)·sin(2π·3000·n/16000)
"""
from __future__ import annotations

import json
import sys

import numpy as np

from .decode import fbank

N = 8000


def signal() -> np.ndarray:
    n = np.arange(N, dtype=np.float64)
    x = (0.3 * np.sin(2 * np.pi * 440 * n / 16000) + 0.2 * np.sin(2 * np.pi * 1234.5 * n / 16000)
         + 0.05 * (n / 8000) * np.sin(2 * np.pi * 3000 * n / 16000))
    return x.astype(np.float32)


def main(out: str) -> None:
    f = fbank(signal())
    json.dump({"samples": N, "frames": [[round(float(v), 5) for v in row] for row in f]}, open(out, "w"))
    print(f"{out}: {f.shape[0]} frames × {f.shape[1]} bins")


if __name__ == "__main__":
    main(sys.argv[1])
