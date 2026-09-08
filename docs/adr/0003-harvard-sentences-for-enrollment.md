# 0003 — Harvard Sentences for voice enrollment, bundled models for FluidAudio

## Status

Accepted (2026-09-08)

## Context

[[0002]] established enrollment as a one-time recording used to extract a speaker embedding via
FluidAudio. Two open questions needed resolving: what the user actually says during enrollment,
and whether FluidAudio's default model-loading behavior is compatible with this app's zero-
network requirement.

On the first: an enrollment recording needs broad phonetic coverage to produce a robust speaker
embedding, not just a few seconds of arbitrary speech. Scripted reading (vs. free-form talking)
also removes the "what do I even say" hesitation for the primary user and gives a known reference
transcript to sanity-check the recording against.

On the second: research (`docs/research-existing-resources.md`) confirmed FluidAudio itself makes
no network calls during inference — but its default behavior downloads its CoreML models from
Hugging Face on first use. Left as default behavior, that would make the app's very first launch
network-dependent, contradicting the requirement that the app work identically with any
connectivity state, including none at all, ever.

## Decision

**Enrollment uses the Harvard Sentences** (IEEE Recommended Practice for Speech Quality
Measurements, 1965 revised list; public domain) — 2 of the 72 ten-sentence lists (20 sentences),
displayed on screen for the primary user to read aloud during first-run onboarding. Chosen for
being purpose-built for phonetic balance, free of any licensing concern, and short enough (~1.5-2
minutes of actual speech) to fit comfortably inside the 5-minute total setup budget alongside
instructions and permission prompts.

**FluidAudio's models are bundled into the app at build time**, not fetched at runtime. This is a
deliberate deviation from FluidAudio's documented default (runtime download from Hugging Face on
first use) specifically to satisfy this app's zero-network requirement from the very first launch
onward.

## Consequences

- Larger app bundle size (bundled models vs. on-demand download) — acceptable trade-off for a
  personal-install / non-App-Store-size-limited distribution; worth re-checking if this app is
  ever distributed more broadly (App Store has bundle-size-dependent download behavior, though no
  hard block).
- Bundling models ourselves means we own tracking FluidAudio version/model compatibility manually
  on upgrade, rather than always getting the latest model automatically — an explicit choice of
  reliability/offline-guarantee over always-latest-model convenience.
- Enrollment content (which sentences, in what order) is now a concrete, fixed asset in the repo
  rather than an open design question.
