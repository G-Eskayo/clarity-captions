"""Model folder sizes for the size-options table (#150): bytes on disk and deflate-zipped bytes (an App Store
download is compressed, so the zipped size approximates what a user downloads)."""
from __future__ import annotations

import json
import os
import tempfile
import zipfile
from pathlib import Path


def dir_bytes(path: Path) -> int:
    path = Path(path)
    if path.is_file():
        return path.stat().st_size
    return sum(f.stat().st_size for f in path.rglob("*") if f.is_file() and not f.is_symlink())


def zipped_bytes(path: Path) -> int:
    """Size of a maximum-compression zip of the folder, written to a temp file and removed."""
    path = Path(path)
    fd, tmp = tempfile.mkstemp(suffix=".zip")
    os.close(fd)
    try:
        with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            files = [path] if path.is_file() else sorted(f for f in path.rglob("*") if f.is_file() and not f.is_symlink())
            for f in files:
                z.write(f, f.relative_to(path.parent if path.is_file() else path))
        return Path(tmp).stat().st_size
    finally:
        os.unlink(tmp)


def record(out: Path, model: str, folder: Path, method: str, license_note: str, encoder: Path | None = None) -> dict:
    """Upsert one model's sizes into a JSON file keyed by model name."""
    out = Path(out)
    data = json.loads(out.read_text()) if out.exists() else {}
    row = {"model": model, "method": method, "license": license_note,
           "disk_bytes": dir_bytes(folder), "zipped_bytes": zipped_bytes(folder)}
    if encoder is not None:
        row["encoder_disk_bytes"] = dir_bytes(encoder)
    data[model] = row
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2) + "\n")
    return row
