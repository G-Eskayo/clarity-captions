"""Bit widths for the low-bit Parakeet Ultra builds (#203 "2-bit north star, English first").

The uniform builds give every encoder weight the same width. The mixed build keeps the parts that low-bit studies find
most sensitive wider: the subsampling front end and the first and last conformer blocks at 6 bits, attention
projections at 4, and the feed-forward and convolution weights of the middle blocks (most of the encoder) at 2.
The lower mixed build (`ultra-mixed24`, Decision mixed-layout on #219: build both) keeps only the front end and the first
and last blocks at 4 bits and puts everything else, attention included, at 2: about 2.2 bits, closer to a true 2-bit
size. Pure functions over const names, so the plan is testable without coremltools.
"""
from __future__ import annotations

import re

UNIFORM_BITS = {"ultra-pal6": 6, "ultra-pal4": 4, "ultra-pal3": 3, "ultra-pal2": 2}
# layout name -> (bits for the front end and the first and last blocks, attention bits, feed-forward/convolution bits)
MIXED_PLANS = {"ultra-mixed246": (6, 4, 2), "ultra-mixed24": (4, 2, 2)}

_BLOCK = re.compile(r"(?:^|[._])layers[._](\d+)(?:[._]|$)")


def block_index(name: str) -> int | None:
    m = _BLOCK.search(name)
    return int(m.group(1)) if m else None


def _in_block_bits(name: str, attn: int, ffconv: int) -> int:
    if "self_attn" in name:
        return attn
    if "feed_forward" in name or "conv" in name:
        return ffconv
    raise ValueError(f"unknown weight inside a conformer block: {name}")


def mixed_plan(names: list[str], layout: str = "ultra-mixed246") -> dict[str, int]:
    """name -> bits. Depth is read from the names; a name set with no block index is refused (renamed export)."""
    edge, attn, ffconv = MIXED_PLANS[layout]
    idx = {n: block_index(n) for n in names}
    blocks = [i for i in idx.values() if i is not None]
    if not blocks:
        raise ValueError("no conformer block index in any weight name; the export's naming changed")
    last = max(blocks)
    plan = {}
    for n, i in idx.items():
        plan[n] = edge if i is None or i in (0, last) else _in_block_bits(n, attn, ffconv)
    return plan


def average_bits(plan: dict[str, int], sizes: dict[str, int]) -> float:
    """Weight-count-weighted mean bit width; every planned weight needs a size."""
    missing = [n for n in plan if n not in sizes]
    if missing:
        raise ValueError(f"no size for {len(missing)} weight(s), e.g. {missing[0]}")
    total = sum(sizes[n] for n in plan)
    return sum(plan[n] * sizes[n] for n in plan) / total
