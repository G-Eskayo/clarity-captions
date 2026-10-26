"""Cut the FLEURS test splits into gender-stratified shards of 16 kHz mono WAV + manifest (#158).

Same shard format as EdAcc's (shards.py), one shard set per language under <out>/<lang>/. Reads the pinned
`data/<config>/test.tsv` and `data/<config>/audio/test.tar.gz` of google/fleurs. Method:
docs/perf/language-accuracy-design.md.
"""
from __future__ import annotations

import io
import json
import re
import tarfile
from dataclasses import asdict, dataclass
from pathlib import Path

from .shards import TARGET_SR, assign_shards, shard_count


@dataclass(frozen=True)
class Language:
    config: str             # FLEURS config name
    locales: tuple          # Apple SpeechTranscriber locales to run


LANGUAGES = {
    "es": Language("es_419", ("es-MX", "es-US", "es-ES")),  # FLEURS Spanish is Latin American; Apple has no es-419
    "fr": Language("fr_fr", ("fr-FR",)),
    "de": Language("de_de", ("de-DE",)),
}


@dataclass(frozen=True)
class FleursClip:
    clip_id: str
    file_name: str
    group: str              # sentence id: the bootstrap unit (FLEURS has no speaker ids)
    reference: str          # raw transcription (case, punctuation, digits)
    audio_seconds: float
    gender: str


def read_tsv(path: Path, lang: str) -> list[FleursClip]:
    """FLEURS test.tsv (no header): id, file name, raw transcription, transcription, characters, samples, gender."""
    clips: list[FleursClip] = []
    seen: set[str] = set()
    for n, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        cols = line.split("\t")
        if len(cols) < 7:
            raise ValueError(f"{path} line {n}: expected 7 tab-separated fields, got {len(cols)}")
        sid, fname, raw, _, _, samples, gender = cols[:7]
        clip_id = f"{lang}-test-" + re.sub(r"[^A-Za-z0-9._-]", "_", Path(fname).stem)
        if clip_id in seen:
            raise ValueError(f"{path}: duplicate clip {clip_id}")
        seen.add(clip_id)
        clips.append(FleursClip(clip_id=clip_id, file_name=fname, group=f"{lang}-{sid}", reference=raw,
                                audio_seconds=round(int(samples) / 16000, 3), gender=gender.strip().lower()))
    return clips


def _to_16k_mono(data: bytes):
    import numpy as np
    import soundfile as sf
    from math import gcd
    from scipy.signal import resample_poly

    samples, sr = sf.read(io.BytesIO(data), dtype="float32", always_2d=True)
    mono = samples.mean(axis=1)
    if sr != TARGET_SR:
        g = gcd(sr, TARGET_SR)
        mono = resample_poly(mono, TARGET_SR // g, sr // g).astype(np.float32)
    return np.clip(mono, -1.0, 1.0)


def _build_language(corpus_dir: Path, out_dir: Path, lang: str, target_hours: float) -> dict:
    import soundfile as sf

    cfg = LANGUAGES[lang]
    src = Path(corpus_dir) / cfg.config
    clips = read_tsv(src / "test.tsv", lang)
    n = shard_count(sum(c.audio_seconds for c in clips), target_hours)
    shards = assign_shards(clips, n, key="gender")
    names = [f"shard-{k + 1:03d}" for k in range(n)]
    where = {}
    for name, members in zip(names, shards):
        (out_dir / name / "audio").mkdir(parents=True, exist_ok=True)
        for c in members:
            where[c.file_name] = (name, c)
    written: set[str] = set()
    with tarfile.open(src / "test.tar.gz", "r:gz") as tar:  # streamed: one member in memory at a time
        for member in tar:
            if not member.isfile():
                continue
            hit = where.get(Path(member.name).name)
            if hit is None:
                continue
            name, c = hit
            wav = out_dir / name / "audio" / f"{c.clip_id}.wav"
            tmp = wav.with_suffix(".wav.tmp")
            sf.write(tmp, _to_16k_mono(tar.extractfile(member).read()), TARGET_SR, format="WAV", subtype="PCM_16")
            tmp.replace(wav)
            written.add(c.file_name)
    missing = sorted(set(where) - written)
    if missing:
        raise FileNotFoundError(f"{lang}: {len(missing)} clip(s) not in the tarball, e.g. {missing[0]}")
    for name, members in zip(names, shards):
        manifest = out_dir / name / "manifest.jsonl"
        tmp = manifest.with_suffix(".jsonl.tmp")
        with tmp.open("w", encoding="utf-8") as fh:
            for c in members:
                row = {"clip_id": c.clip_id, "file": f"audio/{c.clip_id}.wav", "split": "test", "speaker": "",
                       "accent": cfg.config, "gender": c.gender, "language": lang, "locale": list(cfg.locales),
                       "group": c.group, "reference": c.reference, "audio_seconds": c.audio_seconds}
                fh.write(json.dumps(row, ensure_ascii=False) + "\n")
        tmp.replace(manifest)
    summary = {"language": lang, "config": cfg.config, "locales": list(cfg.locales), "n_shards": n,
               "clips": len(clips), "sentences": len({c.group for c in clips}),
               "audio_hours": round(sum(c.audio_seconds for c in clips) / 3600, 3), "shards": names,
               "target_hours": target_hours}
    (out_dir / "index.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def build_fleurs_shards(corpus_dir: Path, out_dir: Path, languages: list[str] | None = None,
                        target_hours: float = 1.0) -> dict:
    """Writes <out>/<lang>/{index.json, shard-NNN/{audio/*.wav, manifest.jsonl}}. Rerunnable."""
    return {lang: _build_language(Path(corpus_dir), Path(out_dir) / lang, lang, target_hours)
            for lang in (languages or list(LANGUAGES))}
