"""Resumable per-shard engine loop: one JSON line per (clip, engine, model, repeat), flushed as it goes (#145)."""
from __future__ import annotations

import datetime as dt
import json
import os
import sys
import time
from pathlib import Path
from typing import Callable

from .results import ResultKey, done_keys


def _ensure_trailing_newline(path: Path) -> None:
    """A crash mid-write leaves a partial last line; start the next append on a fresh line."""
    if path.exists() and path.stat().st_size > 0:
        with path.open("rb") as fh:
            fh.seek(-1, os.SEEK_END)
            if fh.read(1) != b"\n":
                with path.open("ab") as out:
                    out.write(b"\n")


def run_loop(manifest: list[dict], shard_dir: Path, results: Path, *, engine: str, model: str, version: str,
             repeats: int, transcribe: Callable[[Path], str], shard_number: int, host: str,
             on_progress: Callable[[int, int, float | None], None] | None = None) -> dict:
    shard_dir, results = Path(shard_dir), Path(results)
    results.parent.mkdir(parents=True, exist_ok=True)
    done = done_keys(results)
    _ensure_trailing_newline(results)
    total = len(manifest) * repeats
    finished = sum(1 for rep in range(1, repeats + 1) for c in manifest
                   if ResultKey(c["clip_id"], engine, model, rep) in done)
    errors = 0
    ran_audio = ran_proc = 0.0
    remaining_audio = sum(float(c.get("audio_seconds", 0)) for rep in range(1, repeats + 1) for c in manifest
                          if ResultKey(c["clip_id"], engine, model, rep) not in done)
    with results.open("a", encoding="utf-8") as fh:
        for rep in range(1, repeats + 1):
            for c in manifest:
                key = ResultKey(c["clip_id"], engine, model, rep)
                if key in done:
                    continue
                path = shard_dir / c["file"]
                audio_s = float(c.get("audio_seconds", 0))
                remaining_audio -= audio_s
                if not path.exists():
                    errors += 1
                    print(f"ENGINE-EVAL-ERROR {engine}/{model} {c['clip_id']}: missing audio", file=sys.stderr)
                    continue
                t0 = time.perf_counter()
                try:
                    text = transcribe(path)
                except Exception as exc:  # one bad clip must not stop the shard
                    errors += 1
                    print(f"ENGINE-EVAL-ERROR {engine}/{model} {c['clip_id']}: {exc}", file=sys.stderr)
                    continue
                proc = time.perf_counter() - t0
                row = {"clip_id": c["clip_id"], "shard": shard_number, "accent": c.get("accent", ""),
                       "engine": engine, "model": model, "engine_version": version, "repeat": rep,
                       "hypothesis": text or "", "audio_seconds": audio_s, "processing_seconds": round(proc, 4),
                       "host": host, "finished_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}
                fh.write(json.dumps(row, ensure_ascii=False) + "\n")
                fh.flush()
                finished += 1
                ran_audio += audio_s
                ran_proc += proc
                if on_progress:
                    eta = remaining_audio * (ran_proc / ran_audio) if ran_audio else None
                    on_progress(finished, total, eta)
    return {"done": finished, "total": total, "errors": errors}
