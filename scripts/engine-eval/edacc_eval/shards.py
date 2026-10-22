"""Cut the EdAcc parquet files into accent-stratified shards of 16 kHz mono WAV + manifest (#145)."""
from __future__ import annotations

import io
import json
import math
import re
from collections import defaultdict
from dataclasses import asdict, dataclass
from math import gcd
from pathlib import Path

from .normalize import normalize

TARGET_SR = 16000
IGNORE_MARKER = "IGNORE_TIME_SEGMENT_IN_SCORING"


@dataclass(frozen=True)
class Clip:
    clip_id: str
    split: str
    speaker: str
    accent: str
    l1: str
    gender: str
    reference: str
    audio_seconds: float
    source_file: str
    row: int


def clip_id_for(split: str, path: str) -> str:
    stem = Path(path).stem
    return f"{split}-" + re.sub(r"[^A-Za-z0-9._-]", "_", stem)


def shard_count(total_seconds: float, target_hours: float) -> int:
    return max(1, math.ceil(total_seconds / (target_hours * 3600)))


def assign_shards(clips: list[Clip], n_shards: int) -> list[list[Clip]]:
    """Within each accent, sort by clip id and deal round-robin; the deal continues across accents so small
    accents don't all land in shard 1. Deterministic regardless of input order."""
    ids = [c.clip_id for c in clips]
    if len(ids) != len(set(ids)):
        dupes = sorted({i for i in ids if ids.count(i) > 1})
        raise ValueError(f"duplicate clip ids: {dupes[:5]}")
    by_accent: dict[str, list[Clip]] = defaultdict(list)
    for c in clips:
        by_accent[c.accent].append(c)
    shards: list[list[Clip]] = [[] for _ in range(n_shards)]
    cursor = 0
    for accent in sorted(by_accent):
        for c in sorted(by_accent[accent], key=lambda c: c.clip_id):
            shards[cursor % n_shards].append(c)
            cursor += 1
    return shards


def _split_of(parquet: Path) -> str:
    return parquet.name.split("-")[0]


def _scan(corpus_dir: Path) -> tuple[list[Clip], dict[str, int]]:
    import pyarrow.parquet as pq

    clips: list[Clip] = []
    excluded = {"ignore_marker": 0, "empty_reference": 0}
    for parquet in sorted(Path(corpus_dir).glob("*.parquet")):
        split = _split_of(parquet)
        table = pq.read_table(parquet, columns=["speaker", "text", "accent", "l1", "gender", "audio"])
        cols = {name: table.column(name).to_pylist() for name in ["speaker", "text", "accent", "l1", "gender"]}
        audio = table.column("audio")
        for i in range(table.num_rows):
            text = cols["text"][i] or ""
            if text.strip() == IGNORE_MARKER:
                excluded["ignore_marker"] += 1
                continue
            if not normalize(text):
                excluded["empty_reference"] += 1
                continue
            a = audio[i].as_py()
            seconds = _wav_seconds(a["bytes"])
            clips.append(Clip(clip_id=clip_id_for(split, a["path"]), split=split, speaker=cols["speaker"][i],
                              accent=cols["accent"][i], l1=cols["l1"][i], gender=cols["gender"][i],
                              reference=text, audio_seconds=round(seconds, 3), source_file=parquet.name, row=i))
        del table, audio
    return clips, excluded


def _wav_seconds(data: bytes) -> float:
    import soundfile as sf

    info = sf.info(io.BytesIO(data))
    return info.frames / info.samplerate


def _to_16k_mono(data: bytes):
    import numpy as np
    import soundfile as sf
    from scipy.signal import resample_poly

    samples, sr = sf.read(io.BytesIO(data), dtype="float32", always_2d=True)
    mono = samples.mean(axis=1)
    if sr != TARGET_SR:
        g = gcd(sr, TARGET_SR)
        mono = resample_poly(mono, TARGET_SR // g, sr // g).astype(np.float32)
    return np.clip(mono, -1.0, 1.0)


def build_shards(corpus_dir: Path, out_dir: Path, target_hours: float = 1.0) -> dict:
    """Writes out_dir/shard-NNN/{audio/*.wav, manifest.jsonl} and out_dir/index.json. Rerunnable: existing WAVs
    are rewritten, manifests replaced atomically. Streams one parquet at a time."""
    import pyarrow.parquet as pq
    import soundfile as sf

    corpus_dir, out_dir = Path(corpus_dir), Path(out_dir)
    clips, excluded = _scan(corpus_dir)
    n = shard_count(sum(c.audio_seconds for c in clips), target_hours)
    shards = assign_shards(clips, n)
    names = [f"shard-{k + 1:03d}" for k in range(n)]
    where: dict[tuple[str, int], tuple[str, Clip]] = {}
    for name, members in zip(names, shards):
        (out_dir / name / "audio").mkdir(parents=True, exist_ok=True)
        for c in members:
            where[(c.source_file, c.row)] = (name, c)
    for parquet in sorted(corpus_dir.glob("*.parquet")):
        audio = pq.read_table(parquet, columns=["audio"]).column("audio")
        for i in range(len(audio)):
            hit = where.get((parquet.name, i))
            if hit is None:
                continue
            name, c = hit
            wav = out_dir / name / "audio" / f"{c.clip_id}.wav"
            tmp = wav.with_suffix(".wav.tmp")
            sf.write(tmp, _to_16k_mono(audio[i].as_py()["bytes"]), TARGET_SR, format="WAV", subtype="PCM_16")
            tmp.replace(wav)
        del audio
    for name, members in zip(names, shards):
        manifest = out_dir / name / "manifest.jsonl"
        tmp = manifest.with_suffix(".jsonl.tmp")
        with tmp.open("w", encoding="utf-8") as fh:
            for c in members:
                row = asdict(c)
                row["file"] = f"audio/{c.clip_id}.wav"
                fh.write(json.dumps(row, ensure_ascii=False) + "\n")
        tmp.replace(manifest)
    summary = {"n_shards": n, "clips": len(clips), "excluded": excluded,
               "audio_hours": round(sum(c.audio_seconds for c in clips) / 3600, 3),
               "accents": len({c.accent for c in clips}), "speakers": len({c.speaker for c in clips}),
               "shards": names, "target_hours": target_hours}
    (out_dir / "index.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def read_manifest(shard_dir: Path, check_audio: bool = False) -> list[dict]:
    shard_dir = Path(shard_dir)
    rows = [json.loads(l) for l in (shard_dir / "manifest.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
    if check_audio:
        missing = [r["file"] for r in rows if not (shard_dir / r["file"]).exists()]
        if missing:
            raise FileNotFoundError(f"{len(missing)} clip(s) missing audio, e.g. {missing[0]}")
    return rows
