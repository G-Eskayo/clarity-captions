# 0005 — Multiple, bounded reference embeddings per tone (not one blended embedding)

## Status

**Superseded by [[0008]] (2026-09-08)** — own-voice filtering (the feature this data model served)
was replaced by speaker-turn labeling, which needs no reference embeddings at all. Kept for its
reasoning, not part of the build.

Originally: Accepted (2026-09-08)

## Context

Enrollment now covers multiple emotional-tone reference samples ([[0003]] for the base scripted
enrollment; emotional-tone samples added via supplemental enrollment sessions). Two ways to use
them for own-voice matching: average everything into one blended reference embedding, or keep
each sample as a separate stored embedding and match a live utterance against the closest one.

Blending is simpler (one comparison per utterance) but risks "smearing" the profile — an average
of neutral + angry + sad + happy speech could end up a worse match for any single tone than a
tone-specific reference would be, partially defeating the reason tone samples were collected at
all.

The concern raised against keeping them separate was real-time performance: does comparing
against N embeddings instead of 1 slow down live captioning? It doesn't, meaningfully — speaker
embeddings are small (on the order of ~192 dimensions), so a cosine-similarity comparison is a
handful of floating-point operations. The cost of comparing against 10 embeddings vs. 1 is
negligible next to the cost of extracting the embedding from live audio in the first place, which
happens once per utterance regardless of how many reference embeddings exist. Performance was
never actually the limiting factor here.

## Decision

**Keep multiple stored reference embeddings, one per tone, not a single blended average.** A live
utterance is classified as the primary user's if it's close enough (by cosine similarity) to *any*
stored reference embedding.

**Bound the set**: one slot per named tone (neutral from initial enrollment, plus whatever
emotional tones are offered via supplemental sessions). A new supplemental session for a given
tone replaces that tone's stored embedding rather than accumulating additional ones. This is a
design-hygiene decision, not a performance one — even a much larger set would still compare in
negligible time — it exists so the profile stays a small, reasoned-about set rather than growing
unbounded over months/years of use.

## Consequences

- Slightly more on-device storage than a single embedding (still trivially small — a handful of
  small vectors, not a meaningful footprint).
- Matching logic needs a "closest of N" comparison instead of "closest of 1" — negligible added
  code complexity, no meaningful added latency.
- Replacing a tone's embedding on re-recording means a bad supplemental session (e.g. she was
  interrupted, background noise) can be intentionally redone to overwrite it — a feature, not a
  gap, since there's no reason to keep an inferior sample once a better one for the same tone
  exists.
