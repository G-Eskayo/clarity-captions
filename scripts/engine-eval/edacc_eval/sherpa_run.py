"""sherpa-onnx engine (Linux CPU, 2012 Mac mini) over one shard (#145)."""
from __future__ import annotations

import datetime as dt
import json
import socket
from pathlib import Path

from .runner import run_loop
from .shards import read_manifest

ENGINE = "sherpa-onnx"


def make_transcriber(model_dir: Path, threads: int):
    import sherpa_onnx
    import soundfile as sf

    model_dir = Path(model_dir)
    rec = sherpa_onnx.OfflineRecognizer.from_transducer(
        encoder=str(model_dir / "encoder.int8.onnx"), decoder=str(model_dir / "decoder.int8.onnx"),
        joiner=str(model_dir / "joiner.int8.onnx"), tokens=str(model_dir / "tokens.txt"),
        num_threads=threads, model_type="nemo_transducer", decoding_method="greedy_search")

    def transcribe(path: Path) -> str:
        samples, sr = sf.read(str(path), dtype="float32")
        stream = rec.create_stream()
        stream.accept_waveform(sr, samples)
        rec.decode_stream(stream)
        return stream.result.text.strip()

    return transcribe, sherpa_onnx.__version__


def run_shard(shard_dir: Path, results: Path, model_dir: Path, repeats: int, threads: int,
              status: Path | None = None) -> dict:
    shard_dir = Path(shard_dir)
    manifest = read_manifest(shard_dir)
    transcribe, version = make_transcriber(model_dir, threads)
    shard_number = int(shard_dir.name.split("-")[-1])

    def progress(done: int, total: int, eta: float | None) -> None:
        if status:
            Path(status).write_text(json.dumps({
                "engine": ENGINE, "shard": shard_dir.name, "done": done, "total": total,
                "eta_seconds": None if eta is None else round(eta),
                "updated": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}) + "\n")

    return run_loop(manifest, shard_dir, results, engine=ENGINE, model=Path(model_dir).name,
                    version=f"sherpa-onnx {version}, {threads} threads", repeats=repeats, transcribe=transcribe,
                    shard_number=shard_number, host=socket.gethostname(), on_progress=progress)


def stream_latency_loop(manifest: list[dict], shard_dir: Path, out: Path, *, decode, load, engine: str, model: str,
                        hop: float, max_clip_seconds: float) -> int:
    """Growing-window latency lines for clips up to max_clip_seconds, resumable by (stream, clip, engine, model).
    decode(samples, n) transcribes samples[:n]; load(path) returns 16 kHz float samples."""
    import time
    from .latency import growing_window

    out = Path(out)
    done = set()
    if out.exists():
        for raw in out.read_text(encoding="utf-8").splitlines():
            try:
                d = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if isinstance(d, dict) and d.get("kind") == "stream":
                done.add((d.get("clip_id"), d.get("engine"), d.get("model")))
    method = f"growing window, re-decode all audio so far, hop {hop} s, simulated clock + measured compute"
    ran = 0
    with out.open("a", encoding="utf-8") as fh:
        for c in manifest:
            if float(c["audio_seconds"]) > max_clip_seconds or (c["clip_id"], engine, model) in done:
                continue
            samples = load(Path(shard_dir) / c["file"])

            def dec(a: float):
                n = min(len(samples), int(round(a * 16000)))
                t0 = time.perf_counter()
                text = decode(samples, n)
                return text, time.perf_counter() - t0

            ups = growing_window(len(samples) / 16000, hop, dec)
            fh.write(json.dumps({"kind": "stream", "clip_id": c["clip_id"], "engine": engine, "model": model,
                                 "method": method, "audio_seconds": c["audio_seconds"],
                                 "updates": [{"t": t, "text": x} for t, x in ups]}, ensure_ascii=False) + "\n")
            fh.flush()
            ran += 1
    return ran


def run_latency(shard_dir: Path, out: Path, model_dir: Path, threads: int, hop: float = 0.5,
                max_clip_seconds: float = 30.0) -> int:
    import sherpa_onnx
    import soundfile as sf

    model_dir = Path(model_dir)
    rec = sherpa_onnx.OfflineRecognizer.from_transducer(
        encoder=str(model_dir / "encoder.int8.onnx"), decoder=str(model_dir / "decoder.int8.onnx"),
        joiner=str(model_dir / "joiner.int8.onnx"), tokens=str(model_dir / "tokens.txt"),
        num_threads=threads, model_type="nemo_transducer", decoding_method="greedy_search")

    def decode(samples, n):
        stream = rec.create_stream()
        stream.accept_waveform(16000, samples[:n])
        rec.decode_stream(stream)
        return stream.result.text.strip()

    def load(path: Path):
        data, sr = sf.read(str(path), dtype="float32")
        return data

    return stream_latency_loop(read_manifest(Path(shard_dir)), shard_dir, out, decode=decode, load=load,
                               engine=ENGINE, model=model_dir.name, hop=hop, max_clip_seconds=max_clip_seconds)
