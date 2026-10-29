"""Cut ivrit.ai's gated Hebrew eval sets (eval-d1, eval-whatsapp) into the shard format (#201 follow-up).

Each set is one parquet file (`audio` {bytes, path}, `uuid`, `text`) at a pinned revision, fetched with a Hugging Face
token after accepting ivrit.ai's terms. Clips are whole recordings (eval-d1: about 5 minutes of a two-person podcast;
eval-whatsapp: voice notes up to about 5 minutes), so each clip is its own bootstrap group. Same manifest format as
FLEURS (fleurs.py), one shard per set under <out>/<set>/. Method: docs/perf/hebrew-accuracy-design.md.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

from .fleurs import _to_16k_mono
from .shards import TARGET_SR


@dataclass(frozen=True)
class EvalSet:
    repo: str
    revision: str           # dataset commit, pinned
    file: str               # the one parquet file in the repo


SETS = {
    "eval-d1": EvalSet("ivrit-ai/eval-d1", "7899b0427df2e1d722c043ac41211ac7da15c737",
                       "data/test-00000-of-00001.parquet"),
    "eval-whatsapp": EvalSet("ivrit-ai/eval-whatsapp", "1267f61b95b2ecda9368cd620befbdaf8ad60bd8",
                             "data/test-00000-of-00001.parquet"),
}


def clip_id_for(set_name: str, uuid: str) -> str:
    stem = re.sub(r"\.(mp3|ogg|wav|flac|opus)$", "", uuid.strip(), flags=re.I)
    return f"{set_name}-" + re.sub(r"[^A-Za-z0-9._-]+", "_", stem).strip("_")


def build_ivrit_shards(parquet: Path, out_dir: Path, set_name: str) -> dict:
    """Writes <out>/<set>/{index.json, shard-001/{audio/*.wav, manifest.jsonl}}. Rerunnable; the index is written
    last, so a failed run leaves no index and the driver cuts again. O(audio) time, one recording in memory at a time."""
    import pyarrow.parquet as pq
    import soundfile as sf

    spec = SETS[set_name]  # KeyError for an unknown set, before anything is read
    out = Path(out_dir) / set_name
    shard = out / "shard-001"
    pf = pq.ParquetFile(parquet)
    ids: set[str] = set()
    rows: list[dict] = []
    for batch in pf.iter_batches(batch_size=4, columns=["audio", "uuid", "text"]):
        for r in batch.to_pylist():
            cid = clip_id_for(set_name, str(r["uuid"]))
            if cid in ids:
                raise ValueError(f"{set_name}: duplicate clip id {cid}")
            ids.add(cid)
            samples = _to_16k_mono(r["audio"]["bytes"])
            (shard / "audio").mkdir(parents=True, exist_ok=True)
            wav = shard / "audio" / f"{cid}.wav"
            tmp = wav.with_suffix(".wav.tmp")
            sf.write(tmp, samples, TARGET_SR, format="WAV", subtype="PCM_16")
            tmp.replace(wav)
            rows.append({"clip_id": cid, "file": f"audio/{cid}.wav", "split": "test", "speaker": "",
                         "accent": set_name, "set": set_name, "gender": "", "language": "he", "locale": ["he-IL"],
                         "group": cid, "reference": r["text"], "audio_seconds": round(len(samples) / TARGET_SR, 3)})
    manifest = shard / "manifest.jsonl"
    tmp = manifest.with_suffix(".jsonl.tmp")
    tmp.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")
    tmp.replace(manifest)
    summary = {"set": set_name, "repo": spec.repo, "revision": spec.revision, "language": "he", "n_shards": 1,
               "clips": len(rows), "audio_hours": round(sum(r["audio_seconds"] for r in rows) / 3600, 3),
               "shards": ["shard-001"]}
    (out / "index.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary
