"""Sentence splitting for sentence-level models (#159). OPUS-MT (Marian) silently drops sentences from long
multi-sentence inputs, so the runner translates sentence by sentence, as an app integration would."""
from __future__ import annotations

import re
from typing import Callable

# End of sentence, optional closing quotes/brackets, whitespace, then an opening quote/bracket or a capital/digit.
_BOUNDARY = re.compile(r"(?<=[.!?…])([\"'”’)\]]*)\s+(?=[\"'“‘(\[¿¡]?[A-Z0-9À-Ý])")


def split_sentences(text: str) -> list[str]:
    text = text.strip()
    if not text:
        return []
    out, start = [], 0
    for m in _BOUNDARY.finditer(text):
        end = m.end(1)
        out.append(text[start:end].strip())
        start = m.end()
    out.append(text[start:].strip())
    return [s for s in out if s]


def translate_split(lines: list[str], translate_batch: Callable[[list[str]], list[str]]) -> list[str]:
    """Translate each line sentence by sentence in one batch call and rejoin with spaces. O(total sentences)."""
    parts = [split_sentences(l) for l in lines]
    flat = [s for p in parts for s in p]
    outs = translate_batch(flat) if flat else []
    result, i = [], 0
    for p in parts:
        result.append(" ".join(outs[i:i + len(p)]))
        i += len(p)
    return result
