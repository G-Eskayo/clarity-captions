"""Resumable translation loop writing #145 result lines (#159): clip_id = segment id, accent = set name,
hypothesis = translation, audio_seconds = 0, processing_seconds = seconds per line (batch time / batch size)."""
from __future__ import annotations

import datetime as dt
import json
import sys
import time
from pathlib import Path
from typing import Callable, Sequence

from edacc_eval.results import ResultKey, done_keys
from edacc_eval.runner import _ensure_trailing_newline


def run_lines(rows: Sequence[dict], results: Path, *, engine: str, model: str, version: str, repeats: int,
              translate: Callable[[str], str] | None, host: str,
              translate_batch: Callable[[list[str]], list[str]] | None = None, batch_size: int = 1) -> dict:
    """Translate every (segment, repeat) not already in `results`. One line at a time unless translate_batch is
    given (quality runs); speed per caption line is only read from batch-size-1 runs."""
    results = Path(results)
    results.parent.mkdir(parents=True, exist_ok=True)
    done = done_keys(results)
    _ensure_trailing_newline(results)
    total = len(rows) * repeats
    finished = sum(1 for rep in range(1, repeats + 1) for r in rows if ResultKey(r["id"], engine, model, rep) in done)
    errors = 0
    if translate_batch is None:
        if translate is None:
            raise ValueError("need translate or translate_batch")
        batch_size = 1
        translate_batch = lambda lines: [translate(lines[0])]  # noqa: E731
    with results.open("a", encoding="utf-8") as fh:
        for rep in range(1, repeats + 1):
            pending = [r for r in rows if ResultKey(r["id"], engine, model, rep) not in done]
            for start in range(0, len(pending), batch_size):
                batch = pending[start:start + batch_size]
                t0 = time.perf_counter()
                try:
                    outs = translate_batch([r["source"] for r in batch])
                    if len(outs) != len(batch):
                        raise RuntimeError(f"{len(outs)} outputs for {len(batch)} lines")
                except Exception as exc:  # one bad line (or batch) must not stop the run
                    errors += len(batch)
                    print(f"TRANSLATION-EVAL-ERROR {engine}/{model} {batch[0]['id']}: {exc}", file=sys.stderr)
                    continue
                per_line = (time.perf_counter() - t0) / len(batch)
                for r, text in zip(batch, outs):
                    row = {"clip_id": r["id"], "shard": 0, "accent": r["set"], "engine": engine, "model": model,
                           "engine_version": version, "repeat": rep, "hypothesis": text or "", "audio_seconds": 0,
                           "processing_seconds": round(per_line, 6), "batch_size": len(batch), "host": host,
                           "finished_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}
                    fh.write(json.dumps(row, ensure_ascii=False) + "\n")
                fh.flush()
                finished += len(batch)
    return {"done": finished, "total": total, "errors": errors}
