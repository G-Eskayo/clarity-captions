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
