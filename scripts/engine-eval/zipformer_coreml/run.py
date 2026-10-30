"""Run a Core ML build of the zipformer over a shard (accuracy) or a few clips (latency and memory), #220.

    python -m zipformer_coreml.run score --variant pal4 --builds <dir> --shard-dir <shard> --results <jsonl>
    python -m zipformer_coreml.run latency --variant pal4 --builds <dir> --clips <wav>... --out <json>

Scoring writes the #217 harness's result lines (engine "coreml", model zipformer2-66m-he-coreml-<variant>), so
`report-hebrew`'s scorer, normaliser and bootstrap apply unchanged. Each clip decodes like live captions: fbank over
the clip plus the #217 trailing silence, then 1.28 s chunks through the streaming encoder with greedy search.

Latency is computed from measured compute, not by sleeping: with audio arriving in real time, chunk c's audio is
complete at (c + 1) × 1.28 s and its text is ready after that chunk's measured encoder + search time. A token emitted
at encoder frame f of that chunk is shown (chunk end − frame time) + compute after the model placed it. That is the
delay Seal adds on top of the model's own emission lag, which needs word timings these sets don't have.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import resource
import socket
import statistics
import time
from pathlib import Path

import numpy as np

from . import decode as zd

ENGINE = "coreml"
FRAME_SECONDS = 0.04  # one encoder output frame: 32 per 1.28 s chunk (25 Hz)
CHUNK_SECONDS = zd.SHIFT / 100


def model_name(variant: str) -> str:
    return f"zipformer2-66m-he-coreml-{variant}"


class CoreMLZipformer:
    """The three Core ML models of one build, with the encoder states carried between chunks."""

    def __init__(self, folder: Path, compute_units: str = "ALL"):
        import coremltools as ct
        folder = Path(folder)
        cu = getattr(ct.ComputeUnit, compute_units)
        t = time.perf_counter()
        self.encoder = ct.models.MLModel(str(folder / "Encoder.mlpackage"), compute_units=cu)
        self.decoder = ct.models.MLModel(str(folder / "Decoder.mlpackage"), compute_units=cu)
        self.joiner = ct.models.MLModel(str(folder / "Joiner.mlpackage"), compute_units=cu)
        self.load_seconds = time.perf_counter() - t
        self.tokens = zd.read_tokens(folder / "tokens.txt")
        spec = self.encoder.get_spec()
        self.state_inputs = [(i.name, tuple(i.type.multiArrayType.shape), i.type.multiArrayType.dataType)
                             for i in spec.description.input if i.name != "x"]
        self.version = f"coremltools {ct.__version__}, Core ML, compute units {compute_units}"

    def init_states(self) -> list:
        int32 = 131104  # ArrayFeatureType.INT32
        return [np.zeros(shape, np.int32 if dtype == int32 else np.float32) for _, shape, dtype in self.state_inputs]

    def encode(self, x, states):
        out = self.encoder.predict({"x": x, **{n: s for (n, _, _), s in zip(self.state_inputs, states)}})
        return out["encoder_out"], [np.asarray(out["new_" + n]).reshape(s.shape).astype(s.dtype)
                                    for (n, _, _), s in zip(self.state_inputs, states)]

    def decode(self, context):
        return self.decoder.predict({"y": context.astype(np.int32)})["decoder_out"]

    def join(self, enc, dec):
        return self.joiner.predict({"encoder_out": np.asarray(enc, np.float32), "decoder_out": dec})["logit"]

    def transcribe(self, samples: np.ndarray, timings: list | None = None) -> str:
        """timings, if given, receives (chunk index, seconds of compute, tokens emitted so far) per chunk."""
        frames = zd.fbank(zd.pad_for_streaming(samples))
        last = [time.perf_counter()]

        def on_chunk(i, toks):
            now = time.perf_counter()
            if timings is not None:
                timings.append((i, now - last[0], len(toks)))
            last[0] = now

        toks = zd.greedy(frames, self.encode, self.decode, self.join, self.init_states(), on_chunk=on_chunk,
                         on_token=None if timings is None else (lambda i, t: timings.append(("tok", i, t))))
        return zd.to_text(toks, self.tokens)


def token_latencies(events: list) -> tuple[list[float], list[float]]:
    """From transcribe()'s timings: per token, (chunk end − frame time) + that chunk's compute. Returns
    (latency of every token, compute per chunk). O(events)."""
    compute = {}
    toks = []
    for e in events:
        if e[0] == "tok":
            toks.append((e[1], e[2]))
        else:
            compute[e[0]] = e[1]
    lat = [CHUNK_SECONDS - (frame + 1) * FRAME_SECONDS + compute[chunk] for chunk, frame in toks]
    return lat, [compute[k] for k in sorted(compute)]


def _load(path: Path) -> np.ndarray:
    import soundfile as sf
    samples, sr = sf.read(str(path), dtype="float32")
    if sr != zd.SR:
        raise ValueError(f"{path}: {sr} Hz, shards are 16 kHz")
    return samples


def score(variant: str, builds: Path, shard_dir: Path, results: Path, compute_units: str = "ALL",
          status: Path | None = None) -> dict:
    from edacc_eval.runner import run_loop
    from edacc_eval.shards import read_manifest
    shard_dir = Path(shard_dir)
    m = CoreMLZipformer(Path(builds) / variant, compute_units)

    def progress(done, total, eta):
        if status:
            Path(status).write_text(json.dumps({"engine": f"{ENGINE} {model_name(variant)}", "shard": shard_dir.name,
                                                "done": done, "total": total,
                                                "eta_seconds": None if eta is None else round(eta),
                                                "updated": dt.datetime.now(dt.timezone.utc).isoformat(
                                                    timespec="seconds")}) + "\n")

    return run_loop(read_manifest(shard_dir), shard_dir, results, engine=ENGINE, model=model_name(variant),
                    version=m.version, repeats=1, transcribe=lambda p: m.transcribe(_load(p)),
                    shard_number=int(shard_dir.name.split("-")[-1]), host=socket.gethostname(), on_progress=progress)


def latency(variant: str, builds: Path, clips: list[Path], compute_units: str = "ALL", seconds: float = 60.0) -> dict:
    """Load time, first-word and steady latency, compute per chunk and peak memory for one build, over the first
    `seconds` of each clip. Run one build per process: peak memory (ru_maxrss) is per process."""
    m = CoreMLZipformer(Path(builds) / variant, compute_units)
    first, steady, compute = [], [], []
    for i, clip in enumerate(clips):
        ev: list = []
        m.transcribe(_load(clip)[: int(seconds * zd.SR)], timings=ev)
        lat, comp = token_latencies(ev)
        if i == 0:
            comp = comp[1:]  # the first chunk of the run pays for model specialisation, reported as load
        compute += comp
        if lat:
            first.append(lat[0])
            steady += lat[1:]
    q = lambda xs, p: float(np.percentile(xs, p)) if xs else None  # noqa: E731
    return {"variant": variant, "compute_units": compute_units, "clips": len(clips), "seconds_per_clip": seconds,
            "load_seconds": round(m.load_seconds, 3),
            "first_word_seconds_median": q(first, 50), "steady_seconds_median": q(steady, 50),
            "steady_seconds_p95": q(steady, 95), "chunk_compute_ms_median": q([c * 1000 for c in compute], 50),
            "chunk_compute_ms_p95": q([c * 1000 for c in compute], 95),
            "x_realtime": CHUNK_SECONDS / statistics.median(compute) if compute else None,
            "peak_rss_mb": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 2**20, 1),
            "host": socket.gethostname()}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("score")
    s.add_argument("--variant", required=True)
    s.add_argument("--builds", type=Path, required=True)
    s.add_argument("--shard-dir", type=Path, required=True)
    s.add_argument("--results", type=Path, required=True)
    s.add_argument("--compute-units", default="ALL")
    s.add_argument("--status", type=Path)
    la = sub.add_parser("latency")
    la.add_argument("--variant", required=True)
    la.add_argument("--builds", type=Path, required=True)
    la.add_argument("--clips", type=Path, nargs="+", required=True)
    la.add_argument("--out", type=Path, required=True)
    la.add_argument("--compute-units", default="ALL")
    la.add_argument("--seconds", type=float, default=60.0)
    a = ap.parse_args(argv)
    if a.cmd == "score":
        r = score(a.variant, a.builds, a.shard_dir, a.results, a.compute_units, a.status)
        print(f"ZIPFORMER-COREML {a.variant} {a.shard_dir.name} done {r['done']}/{r['total']} errors {r['errors']}")
        return 1 if r["errors"] else 0
    r = latency(a.variant, a.builds, a.clips, a.compute_units, a.seconds)
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(r, indent=2) + "\n")
    print(json.dumps(r))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
