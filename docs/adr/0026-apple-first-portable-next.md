# 0026 — Each feature may ship first on Apple's own frameworks; every feature gets a cross-platform comparison test

## Status

Accepted (owner, 2026-10-26). Extends [[0010]] (all Apple platforms) toward other platforms. Informs #43
"Decide whether to pursue Android and a Chrome extension" without deciding it.

## Context

Seal Speak should be as universal a product as possible, and Android is the obvious next audience. Several
features today lean on Apple-only frameworks: `SpeechAnalyzer` for captions (1.0), `SoundAnalysis` for sound
labels, and, for 1.3, the Translation framework. Others already run on models that aren't tied to Apple:
Parakeet (NVIDIA, CC BY 4.0) is the 1.1 caption engine, and Sortformer (NVIDIA) behind FluidAudio does speaker
labels. The #145 accent test showed that measuring candidates beats guessing: it moved the engine choice from
Apple to Parakeet ([[0025]]).

## Decision

1. **The first version of a feature may use Apple's own framework** when that is the fastest way to ship it well.
2. **Every feature also gets a comparison test** against at least one engine that runs on Android, in the same
   shape as #145: the same checked data for every engine, scored the same way, with confidence intervals, and
   speed measured. The test can run after the Apple version ships.
3. **When a cross-platform engine matches or beats Apple's on the test, prefer it** for the next version, so the
   Android app (if built) can share the same models and behaviour.
4. **A licence check comes before any test**: Seal Speak is paid, so non-commercial licences (CC BY-NC) are out.

## Consequences

- Each feature's ticket set includes a "[E] … comparison test" ticket, tagged with its `feature:` label and
  `feature:android-chrome`.
- Results go in `docs/perf/` and the evidence log, like #145's.
- The landscape and the open questions per feature are in `docs/research/cross-platform-engines.md`.
