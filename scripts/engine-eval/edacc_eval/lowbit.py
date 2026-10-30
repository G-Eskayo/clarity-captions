"""Bit widths for the low-bit Parakeet Ultra builds (#203 "2-bit north star, English first").

The uniform builds give every encoder weight the same width. The mixed build keeps the parts that low-bit studies find
most sensitive wider: the subsampling front end and the first and last conformer blocks at 6 bits, attention
projections at 4, and the feed-forward and convolution weights of the middle blocks (most of the encoder) at 2.
Pure functions over const names, so the plan is testable without coremltools.
"""
from __future__ import annotations

import re

UNIFORM_BITS = {"ultra-pal6": 6, "ultra-pal4": 4, "ultra-pal3": 3, "ultra-pal2": 2}
MIXED_NAME = "ultra-mixed246"

_BLOCK = re.compile(r"(?:^|[._])layers[._](\d+)(?:[._]|$)")


def block_index(name: str) -> int | None:
    m = _BLOCK.search(name)
    return int(m.group(1)) if m else None


def _in_block_bits(name: str) -> int:
    if "self_attn" in name:
        return 4
    if "feed_forward" in name or "conv" in name:
        return 2
    raise ValueError(f"unknown weight inside a conformer block: {name}")


def mixed_plan(names: list[str]) -> dict[str, int]:
    """name -> bits. Depth is read from the names; a name set with no block index is refused (renamed export)."""
    idx = {n: block_index(n) for n in names}
    blocks = [i for i in idx.values() if i is not None]
    if not blocks:
        raise ValueError("no conformer block index in any weight name; the export's naming changed")
    last = max(blocks)
    plan = {}
    for n, i in idx.items():
        plan[n] = 6 if i is None or i in (0, last) else _in_block_bits(n)
    return plan


def average_bits(plan: dict[str, int], sizes: dict[str, int]) -> float:
    """Weight-count-weighted mean bit width; every planned weight needs a size."""
    missing = [n for n in plan if n not in sizes]
    if missing:
        raise ValueError(f"no size for {len(missing)} weight(s), e.g. {missing[0]}")
    total = sum(sizes[n] for n in plan)
    return sum(plan[n] * sizes[n] for n in plan) / total
