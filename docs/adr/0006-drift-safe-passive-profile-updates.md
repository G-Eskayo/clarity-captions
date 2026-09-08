# 0006 — Drift-safe passive profile updates from ongoing usage

## Status

Accepted (2026-09-08)

## Context

Enrollment ([[0003]], [[0005]]) seeds the primary user's reference embeddings, but the profile is
meant to keep improving from ordinary app usage over time, not just from explicit enrollment/
supplemental sessions. The risk: naively updating the reference embedding from every session's
audio could let a misclassification silently drift the profile toward whoever she talks to most —
if a frequent conversation partner's speech is ever wrongly attributed to her even occasionally,
repeated averaging-in would compound that error over time, eventually degrading the exact
distinction the feature exists to make.

## Decision

Passive, automatic profile updates from ordinary usage follow four rules:

1. **High-confidence-only**: a live utterance only contributes to an update when it's classified
   as hers well clear of the decision boundary — borderline utterances are used for that session's
   captioning but never touch the stored profile.
2. **Slow-moving average, small weight per update**: no single session can meaningfully shift the
   profile, good or bad.
3. **Periodic drift check**: the live (usage-updated) profile is periodically compared back
   against the original enrollment embedding for that tone. If they've diverged past a threshold,
   automatic updating pauses and she's prompted to re-enroll rather than the app silently
   continuing on a possibly-corrupted profile.
4. **Manual reset**: a "reset voice profile" option exists in settings regardless, as a direct
   escape hatch independent of the automatic drift check.

## Consequences

- Requires storing the original enrollment embedding separately from the live/updated one per
  tone (for the drift check to have a stable reference point) — a small amount of extra on-device
  storage, not a meaningful cost.
- Slower profile adaptation than a naive "always update" approach — an intentional trade: safety
  against silent degradation over raw responsiveness.
- The drift-check threshold itself is a tunable parameter with no known-correct value yet —
  needs real-world tuning once the app is actually in use, not something to get exactly right
  before shipping.
