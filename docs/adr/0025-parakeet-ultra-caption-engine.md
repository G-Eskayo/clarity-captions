# 0025 — Captions run on Parakeet Ultra (6-bit), with Apple's engine as the fallback

## Status

Proposed (2026-10-22). Would supersede [[0001]]'s engine choice (SpeechAnalyzer) as the default engine; Apple's
engine stays in the app. Extends [[0014]] (bundled models) to the speech model. Design:
`docs/design/parakeet-engine-switch.md`. Accepted only after the owner answers the design's decisions; the
phone checks there gate shipping, not this record.

## Context

The #145 accent test (PR #149) ran four on-device engines over all of EdAcc: 31.4 hours, 122 speakers, 32 accents,
17,528 clips, scored the same way.

| Engine | WER (95% CI) | Correct word on screen, median / p95 (Mac) |
|---|---|---|
| Parakeet Ultra (FluidAudio) | 13.8% (12.7-14.7) | 0.24 / 1.34 s |
| Apple SpeechAnalyzer (today) | 17.2% (16.0-18.4) | 0.67 / 1.86 s |

Ultra had the lowest WER on every shard and every accent group with three or more speakers; the gains are largest on
Nigerian, Kenyan, Spanish and Vietnamese English. Confidence intervals don't overlap with Apple's.

The size test (#150) compressed Ultra's encoder: the 6-bit build (k-means palettization) keeps 13.8% at 498 MB; the
4-bit build gives 14.8% at 350 MB. The owner chose 6-bit, size being no concern, with 4-bit as the fallback, and
moved the switch into 1.1 as build 7 alongside the iPad work.

FluidAudio is already in the app for speaker labels ([[0002]], [[0008]]), at the pinned 0.17.5. A spike confirmed
it loads a compressed Parakeet folder from a local path with no network (`AsrModels.loadLocal`).

## Decision

1. **Default caption engine: Parakeet Ultra, 6-bit encoder**, run through FluidAudio 0.17.5's `AsrManager` with a
   committed tail-window decoder in CaptionCore (finals = words two consecutive decodes agree on; the rest shows
   as the volatile tail). `CaptionUpdate` and everything downstream stay as they are.
2. **Apple's SpeechAnalyzer stays** behind a `SpeechRecognizerBackend` seam and a developer-only flag. The app
   falls back to it automatically when the model is missing or fails to load, on a memory warning, on low available
   memory, or at critical thermal state. Users never see an engine setting ([[0013]]).
3. **The model ships in the app** under [[0014]]'s rules: compiled folder in the bundle, URL passed in with no
   default, `ModelHub.offlineMode` on, fetch script with a checked-in per-file sha256 manifest, project generation
   fails without it. Binaries are never committed.
4. **Credit under CC BY 4.0** in NOTICE.md, the credits screen and the model folder: Moondream's Parakeet Ultra,
   from NVIDIA Parakeet TDT 0.6B v3, Core ML conversion by FluidInference, with the change noted (encoder compressed
   to 6 bits for Seal Speak).
5. **Ships only if the iPhone checks pass** (design section 7: offline load, latency against Apple on the same phone,
   memory with Sortformer, 60-minute heat and battery, real-room accuracy, fallbacks). If 6-bit fails memory or heat,
   4-bit is tried; if both fail, build 7 ships with the flag on Apple.

## Consequences

- About 13.8% instead of 17.2% WER on accented speech, the product's core promise for a deaf user in mixed company.
- The app grows from about 247 MB to about 745 MB on disk. Already over the 200 MB cellular prompt, so no new prompt.
- The first launch after install compiles the model for the phone (35 s on a Mac); first run has to show a step
  for it.
- An offline model in a live loop re-encodes audio: each decode is a full 15 s encoder pass. Battery and heat are
  the main risk, handled by an adaptive decode interval, a silence gate and the thermal fallback.
- The custom vocabulary list only affects the Apple fallback until Parakeet vocabulary boosting is built.
- [[0015]]'s budget exempts model swaps and its baseline is still unmeasured, so the switch is judged against Apple's
  engine measured on the same phone in the same build.
- Two engines to keep working. The seam keeps the Apple path tested with the same fakes.
