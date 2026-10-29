"""The open Hebrew engines for #201, run locally over one shard (resumable, one JSON line per clip, as #145).

- sherpa-onnx streaming transducers (CPU): the ivrit.ai zipformer2 66M and Nemotron 3.5 streaming zero-shot.
- Hugging Face transformers (Apple GPU through MPS): Parakeet-He and ivrit.ai's Whisper large-v3 turbo.

Apple's DictationTranscriber runs in the Swift harness (`engine-eval run --engines apple-dictation`). Nothing here
calls a network service; models are read from local folders fetched by scripts/engine-eval/hebrew-driver.sh.
Method: docs/perf/hebrew-accuracy-design.md.
"""
from __future__ import annotations

import datetime as dt
import json
import socket
from dataclasses import dataclass
from pathlib import Path

from .runner import run_loop
from .shards import read_manifest

SR = 16000


@dataclass(frozen=True)
class EngineSpec:
    engine: str           # the result line's engine field
    model: str            # the result line's model field and the folder under the models dir
    kind: str             # sherpa-online | hf-tdt | hf-whisper
    chunk_seconds: float = 0.0
    language: str = ""    # Nemotron's language prompt


ENGINES = {
    "zipformer": EngineSpec("sherpa-onnx-online", "zipformer2-66m-streaming-he-int8", "sherpa-online", 1.28),
    # Zero-shot: no Hebrew fine-tune, but told the language ("he"), which beat auto-detect on a probe.
    "nemotron": EngineSpec("sherpa-onnx-online", "nemotron-3.5-asr-streaming-0.6b-1120ms-int8", "sherpa-online",
                           1.12, "he"),
    "parakeet-he": EngineSpec("hf-transformers", "parakeet-tdt-0.6b-v3-he", "hf-tdt"),
    "whisper-ivrit": EngineSpec("hf-transformers", "whisper-large-v3-turbo-ivrit", "hf-whisper"),
}


def padded_for_streaming(samples, chunk_seconds: float):
    """Trailing silence of two chunks, so a streaming model emits the last words before input_finished()."""
    import numpy as np
    return np.concatenate([samples, np.zeros(int(2 * chunk_seconds * SR) + SR // 2, dtype=np.float32)])


def _load(path: Path):
    import soundfile as sf
    samples, sr = sf.read(str(path), dtype="float32")
    if sr != SR:
        raise ValueError(f"{path}: {sr} Hz, shards are 16 kHz")
    return samples


def _sherpa_online(spec: EngineSpec, folder: Path, threads: int):
    import sherpa_onnx
    rec = sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=str(folder / "tokens.txt"), encoder=str(folder / "encoder.int8.onnx"),
        decoder=str(folder / "decoder.int8.onnx"), joiner=str(folder / "joiner.int8.onnx"),
        num_threads=threads, decoding_method="greedy_search")

    def transcribe(path: Path) -> str:
        stream = rec.create_stream()
        if spec.language:
            stream.set_option("language", spec.language)
        stream.accept_waveform(SR, padded_for_streaming(_load(path), spec.chunk_seconds))
        stream.input_finished()
        while rec.is_ready(stream):
            rec.decode_stream(stream)
        return rec.get_result(stream).strip()

    lang = f", language {spec.language}" if spec.language else ""
    return transcribe, f"sherpa-onnx {sherpa_onnx.__version__}, streaming, {threads} threads{lang}"


def _device():
    import torch
    return "mps" if torch.backends.mps.is_available() else "cpu"


def _hf_tdt(folder: Path):
    import torch
    import transformers
    from transformers import AutoModelForTDT, AutoProcessor
    device = _device()
    processor = AutoProcessor.from_pretrained(folder)
    model = AutoModelForTDT.from_pretrained(folder).to(device).eval()

    def transcribe(path: Path) -> str:
        inputs = processor(_load(path), sampling_rate=SR, return_tensors="pt").to(device)
        with torch.inference_mode():
            out = model.generate(**inputs)
        return processor.batch_decode(out.sequences, skip_special_tokens=True)[0].strip()

    return transcribe, f"transformers {transformers.__version__}, torch {torch.__version__}, {device}, fp32, greedy"


def _hf_whisper(folder: Path):
    import torch
    import transformers
    from transformers import WhisperForConditionalGeneration, WhisperProcessor
    device = _device()
    dtype = torch.float16 if device == "mps" else torch.float32
    processor = WhisperProcessor.from_pretrained(folder)
    model = WhisperForConditionalGeneration.from_pretrained(folder, torch_dtype=dtype).to(device).eval()

    def transcribe(path: Path) -> str:
        samples = _load(path)
        long = len(samples) > 30 * SR
        inputs = processor(samples, sampling_rate=SR, return_tensors="pt", truncation=not long,
                           padding="longest" if long else "max_length", return_attention_mask=True)
        feats = inputs.input_features.to(device, dtype)
        kw = {"attention_mask": inputs.attention_mask.to(device)} if long else {}
        with torch.inference_mode():
            ids = model.generate(feats, language="he", task="transcribe", num_beams=1, do_sample=False,
                                 return_timestamps=long, **kw)
        return processor.batch_decode(ids, skip_special_tokens=True)[0].strip()

    return transcribe, (f"transformers {transformers.__version__}, torch {torch.__version__}, {device}, "
                        f"{'fp16' if dtype == torch.float16 else 'fp32'}, language he, greedy")


def make_transcriber(spec: EngineSpec, models_dir: Path, threads: int = 8):
    folder = Path(models_dir) / spec.model
    if not folder.is_dir():
        raise FileNotFoundError(f"{folder} missing: fetch it with hebrew-driver.sh")
    if spec.kind == "sherpa-online":
        return _sherpa_online(spec, folder, threads)
    if spec.kind == "hf-tdt":
        return _hf_tdt(folder)
    if spec.kind == "hf-whisper":
        return _hf_whisper(folder)
    raise ValueError(spec.kind)


def run_engine(name: str, shard_dir: Path, results: Path, models_dir: Path, threads: int = 8,
               status: Path | None = None) -> dict:
    spec = ENGINES[name]  # KeyError for an unknown engine, before anything loads
    shard_dir = Path(shard_dir)
    manifest = read_manifest(shard_dir)
    transcribe, version = make_transcriber(spec, models_dir, threads)

    def progress(done: int, total: int, eta: float | None) -> None:
        if status:
            Path(status).write_text(json.dumps({
                "engine": f"{spec.engine} {spec.model}", "shard": shard_dir.name, "done": done, "total": total,
                "eta_seconds": None if eta is None else round(eta),
                "updated": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}) + "\n")

    return run_loop(manifest, shard_dir, results, engine=spec.engine, model=spec.model, version=version, repeats=1,
                    transcribe=transcribe, shard_number=int(shard_dir.name.split("-")[-1]),
                    host=socket.gethostname(), on_progress=progress)
