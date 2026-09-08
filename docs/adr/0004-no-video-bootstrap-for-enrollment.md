# 0004 — Reject bootstrapping enrollment from existing photos/videos

## Status

Accepted (2026-09-08)

## Context

Considered letting the primary user optionally supply existing videos (via `PHPickerViewController`,
which needs no library permission) or Voice Memos from her phone during onboarding, to extract
additional speech and broaden the initial speaker embedding beyond the scripted Harvard Sentences
reading ([[0003]]).

This runs into a real identification problem, not just an inconvenience: at initial setup there is
no reference embedding yet, so the app has no way to tell which voice in a multi-speaker home video
is hers — and device provenance (whether the video was recorded on her own phone) provides no
actual signal about who's speaking in it either. The only real fix is sequencing this *after*
scripted enrollment and reusing the own-voice-matching pipeline ([[0002]]) to filter each candidate
video down to her segments — technically sound, but real added scope (handling videos with no
match, noisy/music-polluted audio, multi-video import UX) for a "nice to have" quality boost that a
mechanism we already have (continuous usage-based improvement) already addresses via a different
path.

## Decision

**Not building video/audio-file bootstrap for enrollment.** Voice profile quality improves solely
through (1) the scripted Harvard Sentences enrollment ([[0003]]) and (2) continuous refinement from
real app usage over time.

## Consequences

- Keeps v1 scope smaller ahead of the 2026-10-25 deadline — no video-import UI, no handling
  degenerate cases (no speech found, wrong speaker matched, poor audio quality).
- If "how effective is this quickly" becomes a real problem in practice once the app is in use,
  the sequenced after-enrollment approach documented above is the known fallback design, not
  something to re-derive from scratch.
