# 0008 — Speaker-turn labeling replaces own-voice filtering

## Status

Accepted (2026-09-08). Supersedes [[0002]]'s own-voice-matching approach and voids [[0003]],
[[0005]], and [[0006]] (all specific to enrollment-based own-voice filtering — kept in the repo
for their reasoning, not deleted, but no longer part of the build).

## Context

An independent review (2026-09-08, pre-implementation) surfaced two decisive problems with the
own-voice-filtering design that [[0001]] through [[0006]] had converged on:

1. **Latency**: real-time speaker-embedding classification realistically lags live speech by
   seconds, not milliseconds. Own-voice filtering would either delay her captions by that much or
   render-then-retract her own words — a real degradation of the core feature for someone relying
   on it to follow a live conversation.
2. **Error asymmetry, unaddressed anywhere**: a false negative (her own speech shown) is a mild
   annoyance. A false positive (someone else's speech wrongly suppressed) is information loss she
   has no way to detect — she doesn't know a sentence was ever said. These failure modes are not
   remotely equivalent, and nothing in the enrollment/threshold design accounted for that.

Separately, the project owner confirmed (2026-09-08) that the app must generalize to anyone who
downloads it, with **no per-user training or enrollment of any kind before it reaches a device** —
it needs to work identically for every user out of the box. Own-voice filtering's entire design
was enrollment-dependent by construction, in direct tension with that.

**Speaker-turn labeling** — showing which of several distinguishable speakers said each line
("Speaker 1: ... / Speaker 2: ...") without identifying *who* any speaker specifically is —
resolves both problems at once:
- Needs no enrollment, no reference embeddings, no per-user data of any kind. Every install
  behaves identically from first launch, satisfying the generalization requirement directly.
- Fails visibly and recoverably: a wrong turn label is obviously wrong to the reader and doesn't
  destroy information the way a wrongly-suppressed line does.
- Uses FluidAudio's diarization output close to natively ([[0002]]'s chosen library already does
  "who spoke when" clustering) — this is a smaller build, not a larger one, than the
  enrollment-based approach it replaces.

## Decision

**Live captioning labels each utterance by speaker turn** (Speaker 1, Speaker 2, ...) using
FluidAudio's diarization, with no voice enrollment, no reference embeddings, and no per-user
model state of any kind, on any device.

## Consequences

- Deletes real scope ahead of 2026-10-25: no Harvard Sentences enrollment flow, no supplemental
  sessions, no emotional-tone recording, no drift-safe update logic, no "reset voice profile"
  settings screen. [[0003]], [[0005]], [[0006]] and their associated onboarding UI are cut.
- Still inherits diarization's real latency characteristics — turn labels may lag slightly behind
  raw transcription, same underlying constraint as before, but the failure mode is now a visibly
  late or occasionally-wrong label rather than lost/delayed/retracted core content.
- Speaker identity is not stable across sessions — "Speaker 1" in one conversation isn't
  guaranteed to map to the same person in a later one, since there's no enrollment to anchor
  identity to. Acceptable: the goal is distinguishing who's talking *right now*, not tracking
  identity over time.
- The app is now testable by anyone, including the project owner himself, without needing the
  intended recipient's voice at all — directly enables his own pre-release testing across
  arbitrary voices/environments before it ever reaches her device.
