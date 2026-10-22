"""Atomic shard claims on the 2012 mini's disk: whoever creates claims/shard-NNN first owns it (mkdir is atomic).
A host restarting takes back its own unfinished claim before claiming a new shard (#145)."""
from __future__ import annotations

import os
from pathlib import Path


def _dir(root: Path, k: int) -> Path:
    return Path(root) / f"shard-{k:03d}"


def owner(root: Path, k: int) -> str | None:
    f = _dir(root, k) / "owner"
    return f.read_text().strip() if f.exists() else None


def claim_next(root: Path, total: int, host: str, first: int = 1) -> int | None:
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    for k in range(first, total + 1):
        d = _dir(root, k)
        if d.exists() and not (d / "done").exists() and owner(root, k) == host:
            return k
    for k in range(first, total + 1):
        d = _dir(root, k)
        try:
            os.mkdir(d)
        except FileExistsError:
            continue
        tmp = d / "owner.tmp"
        tmp.write_text(host + "\n")
        tmp.replace(d / "owner")
        return k
    return None


def mark_done(root: Path, k: int) -> None:
    (_dir(root, k) / "done").write_text("done\n")
