"""python -I -m speaker_onnx.run <engine> ...   (#160)

One recording through one engine and the app's live speaker path, written as the same result JSON `engine-eval
speakers` writes, so `speaker_eval.cli score` scores it unchanged (`<recording>.<label>.r<n>.json`).

  sortformer  an ONNX Sortformer step graph, streamed exactly as the app streams Core ML (fastV2_1 geometry)
  sherpa      sherpa-onnx offline diarization (pyannote segmentation + speaker embeddings + clustering). It needs the
              whole recording first, so every caption request sees the finished result: "offline": true, and its
              first-label latency means nothing. Scored to show what its labels would be worth, not as a live engine.
"""
from __future__ import annotations

import argparse
import json
import platform
import resource
import sys
import time
from pathlib import Path

import numpy as np

from .live_path import SAMPLE_RATE, Seg, replay, wav_chunks
from .sortformer import Config, OnnxSortformer, StreamingSortformer


def peak_mb() -> float:
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024   # Linux: KiB


class Offline:
    """A finished diarization served to the live path: every request sees all of it."""

    def __init__(self, segs):
        self._segs = segs

    def feed(self, samples):
        pass

    @property
    def segments(self):
        return self._segs

    def finish(self):
        pass


def read_all(path: str, max_seconds: float | None) -> np.ndarray:
    x = np.concatenate(list(wav_chunks(path)))
    return x[:int(max_seconds * SAMPLE_RATE)] if max_seconds else x


def load_phrases(path: str, max_seconds: float | None):
    ph = [(p["start"], p["end"]) for p in json.loads(Path(path).read_text())]
    return [p for p in ph if p[1] <= max_seconds] if max_seconds else ph


def sherpa_segments(audio: np.ndarray, a) -> list[Seg]:
    import sherpa_onnx as so
    cfg = so.OfflineSpeakerDiarizationConfig(
        segmentation=so.OfflineSpeakerSegmentationModelConfig(
            pyannote=so.OfflineSpeakerSegmentationPyannoteModelConfig(model=a.seg), num_threads=a.threads),
        embedding=so.SpeakerEmbeddingExtractorConfig(model=a.emb, num_threads=a.threads),
        clustering=so.FastClusteringConfig(num_clusters=a.num_clusters, threshold=a.threshold),
        min_duration_on=a.min_on, min_duration_off=a.min_off)
    if not cfg.validate():
        raise SystemExit("sherpa-onnx config does not validate")
    sd = so.OfflineSpeakerDiarization(cfg)
    return [Seg(int(r.speaker), float(r.start), float(r.end)) for r in sd.process(audio).sort_by_start_time()]


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="speaker_onnx.run")
    p.add_argument("engine", choices=["sortformer", "sherpa"])
    p.add_argument("--audio", required=True)
    p.add_argument("--phrases", required=True)
    p.add_argument("--recording", required=True)
    p.add_argument("--label", required=True, help="model label in the result file name")
    p.add_argument("--out", required=True)
    p.add_argument("--threads", type=int, default=2)
    p.add_argument("--max-seconds", type=float, help="first N seconds only (parity checks; never scored)")
    p.add_argument("--model", help="sortformer: the ONNX step graph")
    p.add_argument("--speakers", type=int, default=4, help="sortformer: speaker slots in the graph")
    p.add_argument("--pad-to", help="sortformer: static graph shapes chunk,spkcache,fifo (e.g. 3048,188,40)")
    p.add_argument("--seg", help="sherpa: pyannote segmentation model.onnx")
    p.add_argument("--emb", help="sherpa: speaker embedding model")
    p.add_argument("--threshold", type=float, default=0.5, help="sherpa: clustering threshold (example default)")
    p.add_argument("--num-clusters", type=int, default=-1, help="sherpa: fixed speaker count; -1 = threshold")
    p.add_argument("--min-on", type=float, default=0.3)
    p.add_argument("--min-off", type=float, default=0.5)
    a = p.parse_args(argv)

    phrases = load_phrases(a.phrases, a.max_seconds)
    t0 = time.monotonic()
    meta = {"engine": a.engine, "threads": a.threads, "host": platform.node(), "cpu": platform.processor() or None}
    if a.engine == "sortformer":
        pad = tuple(int(v) for v in a.pad_to.split(",")) if a.pad_to else None
        model = OnnxSortformer(a.model, threads=a.threads, pad_to=pad)
        d = StreamingSortformer(model, Config(num_speakers=a.speakers))
        load = time.monotonic() - t0
        chunks = (wav_chunks(a.audio) if not a.max_seconds
                  else iter([read_all(a.audio, a.max_seconds)]))
        result = replay(d, chunks, phrases, load_seconds=load)
        meta.update({"model_path": a.model, "onnx_calls": model.calls, "pad_to": pad, "speakers": a.speakers,
                     "offline": False})
    else:
        audio = read_all(a.audio, a.max_seconds)
        t1 = time.monotonic()
        segs = sherpa_segments(audio, a)
        diar_s = time.monotonic() - t1
        result = replay(Offline(segs), iter([audio]), phrases, load_seconds=t1 - t0)
        result["wall_seconds"] = time.monotonic() - t0
        meta.update({"seg": a.seg, "emb": a.emb, "threshold": a.threshold, "num_clusters": a.num_clusters,
                     "min_on": a.min_on, "min_off": a.min_off, "diarize_seconds": diar_s, "offline": True})
    result.update({"recording": a.recording, "model": a.label, "footprint_mb": {"peak": peak_mb()},
                   "finished_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **meta})
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    tmp = Path(a.out).with_suffix(".tmp")
    tmp.write_text(json.dumps(result))
    tmp.replace(a.out)
    print(f"{a.recording} {a.label}: {result['audio_seconds']:.0f} s audio in {result['wall_seconds']:.0f} s, "
          f"{len(result['segments'])} segments, peak {peak_mb():.0f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
